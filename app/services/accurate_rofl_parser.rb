require 'json'

class AccurateRoflParser
  def initialize(file_path)
    @file_path = file_path
  end

  def parse
    Rails.logger.info "Starting AccurateRoflParser with automatic player detection"
    
    begin
      # Extract JSON data containing statsJson (which has all player data)
      json_output = `strings "#{@file_path}" | grep 'statsJson'`
      
      if json_output.empty?
        Rails.logger.error "No statsJson found in ROFL file"
        return { success: false, error: "No statsJson found" }
      end
      
      # Extract the statsJson content
      stats_json_match = json_output.match(/"statsJson":"(\[.*?\])"/)
      unless stats_json_match
        Rails.logger.error "Could not parse statsJson"
        return { success: false, error: "Could not parse statsJson" }
      end
      
      # The statsJson contains an escaped JSON array with all player data
      escaped_json = stats_json_match[1]
      # Unescape the JSON
      unescaped_json = escaped_json.gsub('\\"', '"').gsub('\\\\', '\\')
      
      begin
        # Parse the JSON array of players
        all_players = JSON.parse(unescaped_json)
        Rails.logger.info "Found #{all_players.length} players in statsJson"
      rescue JSON::ParserError => e
        Rails.logger.error "Failed to parse player data: #{e.message}"
        return { success: false, error: "Failed to parse player data: #{e.message}" }
      end
      
      if all_players.nil? || all_players.empty?
        Rails.logger.error "No player data found in ROFL file"
        return { success: false, error: "No player data found" }
      end
      
      # Automatically select the main player using scoring algorithm
      main_player_data = select_main_player(all_players)
      
      if main_player_data.nil? || main_player_data.empty?
        Rails.logger.error "Could not determine main player"
        return { success: false, error: "Could not determine main player" }
      end
      
      # Extract game duration
      time_played = main_player_data['TIME_PLAYED']&.to_i
      
      # Build the result structure with game_info
      {
        success: true,
        header: { magic: "RIOT" },
        metadata: main_player_data,
        game_info: {
          duration: time_played,
          game_duration: time_played,
          champion_name: main_player_data['SKIN'],
          champion_image_url: AccurateRoflParser.get_champion_image_url(main_player_data['SKIN']),
          summoner_name: main_player_data['RIOT_ID_GAME_NAME'],
          summoner_tag: main_player_data['RIOT_ID_TAG_LINE'],
          level: main_player_data['LEVEL']&.to_i,
          kills: main_player_data['CHAMPIONS_KILLED']&.to_i || 0,
          deaths: main_player_data['NUM_DEATHS']&.to_i || 0,
          assists: main_player_data['ASSISTS']&.to_i || 0,
          gold_earned: main_player_data['GOLD_EARNED']&.to_i || 0,
          cs: main_player_data['MINIONS_KILLED']&.to_i || 0,
          vision_score: main_player_data['VISION_SCORE']&.to_i || 0,
          damage_dealt: main_player_data['TOTAL_DAMAGE_DEALT_TO_CHAMPIONS']&.to_i || 0,
          win: main_player_data['WIN'] == 'Win',
          team: main_player_data['TEAM']&.to_i,
          position: main_player_data['INDIVIDUAL_POSITION'] || main_player_data['TEAM_POSITION'],
          items: extract_items_from_player_data(main_player_data),
          items_purchased: main_player_data['ITEMS_PURCHASED']&.to_i || 0
        },
        team_data: organize_players_into_teams(all_players),
        file_info: {
          size: File.size(@file_path),
          name: File.basename(@file_path),
          full_path: @file_path
        }
      }
    rescue => e
      Rails.logger.error "Error in AccurateRoflParser: #{e.message}"
      {
        success: false,
        error: e.message,
        file_info: {
          size: File.exist?(@file_path) ? File.size(@file_path) : 0,
          name: File.basename(@file_path),
          full_path: @file_path
        }
      }
    end
  end

  private

  def organize_players_into_teams(all_players)
    blue_team = []
    red_team = []
    
    all_players.each do |player|
      team_id = player['TEAM']&.to_i
      player_data = {
        summoner_name: player['RIOT_ID_GAME_NAME'],
        summoner_tag: player['RIOT_ID_TAG_LINE'],
        champion: player['SKIN'],
        level: player['LEVEL']&.to_i,
        kills: player['CHAMPIONS_KILLED']&.to_i || 0,
        deaths: player['NUM_DEATHS']&.to_i || 0,
        assists: player['ASSISTS']&.to_i || 0,
        gold_earned: player['GOLD_EARNED']&.to_i || 0,
        cs: player['MINIONS_KILLED']&.to_i || 0,
        vision_score: player['VISION_SCORE']&.to_i || 0,
        damage_dealt: player['TOTAL_DAMAGE_DEALT_TO_CHAMPIONS']&.to_i || 0,
        position: player['INDIVIDUAL_POSITION'] || player['TEAM_POSITION'],
        team: team_id,
        win: player['WIN'] == 'Win'
      }
      
      if team_id == 100
        blue_team << player_data
      elsif team_id == 200
        red_team << player_data
      end
    end
    
    Rails.logger.info "Organize Teams Debug - blue_team: #{blue_team.length} players"
    Rails.logger.info "Organize Teams Debug - red_team: #{red_team.length} players"
    Rails.logger.info "Organize Teams Debug - blue sample: #{blue_team.first&.slice(:summoner_name, :champion, :kills)}"
    Rails.logger.info "Organize Teams Debug - red sample: #{red_team.first&.slice(:summoner_name, :champion, :kills)}"
    
    {
      players: all_players,
      teams: {
        blue_team: blue_team,
        red_team: red_team
      }
    }
  end

  def extract_game_statistics(content)
    # Use system command to extract all JSON data from the file
    begin
      # Extract JSON data containing statsJson (which has all player data)
      json_output = `strings "#{@file_path}" | grep 'statsJson'`
      
      return nil if json_output.empty?
      
      # Debug: Log raw JSON output
      Rails.logger.info "Raw JSON lines found: #{json_output.split("\n").length}"
      
      # Extract the statsJson content
      stats_json_match = json_output.match(/"statsJson":"(\[.*?\])"/)
      if stats_json_match
        # The statsJson contains an escaped JSON array with all player data
        escaped_json = stats_json_match[1]
        # Unescape the JSON
        unescaped_json = escaped_json.gsub('\\"', '"').gsub('\\\\', '\\')
        
        begin
          # Parse the JSON array of players
          players_array = JSON.parse(unescaped_json)
          Rails.logger.info "Found #{players_array.length} players in statsJson"
          
          all_players = []
          players_array.each_with_index do |player_data, index|
            if player_data.is_a?(Hash)
              Rails.logger.info "Player #{index + 1}: #{player_data['RIOT_ID_GAME_NAME']}##{player_data['RIOT_ID_TAG_LINE']} playing #{player_data['SKIN']}"
              all_players << player_data
            end
          end
        rescue JSON::ParserError => e
          Rails.logger.error "Failed to parse statsJson: #{e.message}"
          return nil
        end
      else
        Rails.logger.error "Could not find statsJson in ROFL file"
        return nil
      end
      
      # If we found multiple players, try to identify the replay owner
      # The replay owner is typically the first player or can be identified by file ownership
      stats = select_main_player(all_players)
      
      # Log all players found for debugging
      Rails.logger.info "Found #{all_players.length} players in ROFL file:"
      all_players.each_with_index do |player, index|
        summoner_name = player['RIOT_ID_GAME_NAME'] || 'Unknown'
        summoner_tag = player['RIOT_ID_TAG_LINE'] || ''
        champion = player['SKIN'] || 'Unknown'
        full_name = summoner_tag.empty? ? summoner_name : "#{summoner_name}##{summoner_tag}"
        Rails.logger.info "  Player #{index + 1}: #{full_name} playing #{champion}"
      end
      
      # Log which player was selected
      if stats['RIOT_ID_GAME_NAME']
        selected_name = stats['RIOT_ID_TAG_LINE'] ? "#{stats['RIOT_ID_GAME_NAME']}##{stats['RIOT_ID_TAG_LINE']}" : stats['RIOT_ID_GAME_NAME']
        Rails.logger.info "Selected player: #{selected_name} playing #{stats['SKIN']}"
      end
      
      # Extract TIME_PLAYED (handle escaped quotes)
      time_match = json_output.match(/\\"TIME_PLAYED\\":\\"(\d+)\\"/)
      stats['TIME_PLAYED'] = time_match[1] if time_match
      
      # Extract other key stats
      stats['SKIN'] = extract_value(json_output, 'SKIN')
      stats['CHAMPIONS_KILLED'] = extract_value(json_output, 'CHAMPIONS_KILLED')
      stats['NUM_DEATHS'] = extract_value(json_output, 'NUM_DEATHS')
      stats['ASSISTS'] = extract_value(json_output, 'ASSISTS')
      stats['GOLD_EARNED'] = extract_value(json_output, 'GOLD_EARNED')
      stats['MINIONS_KILLED'] = extract_value(json_output, 'MINIONS_KILLED')
      stats['VISION_SCORE'] = extract_value(json_output, 'VISION_SCORE')
      stats['TOTAL_DAMAGE_DEALT_TO_CHAMPIONS'] = extract_value(json_output, 'TOTAL_DAMAGE_DEALT_TO_CHAMPIONS')
      stats['WIN'] = extract_value(json_output, 'WIN')
      stats['LEVEL'] = extract_value(json_output, 'LEVEL')
      stats['RIOT_ID_GAME_NAME'] = extract_value(json_output, 'RIOT_ID_GAME_NAME')
      stats['RIOT_ID_TAG_LINE'] = extract_value(json_output, 'RIOT_ID_TAG_LINE')
      stats['INDIVIDUAL_POSITION'] = extract_value(json_output, 'INDIVIDUAL_POSITION')
      stats['TEAM'] = extract_value(json_output, 'TEAM')
      
      # Extract additional metadata
      stats['GAME_VERSION'] = extract_value(json_output, 'GAME_VERSION')
      stats['QUEUE_ID'] = extract_value(json_output, 'QUEUE_ID')
      stats['GAME_MODE'] = extract_value(json_output, 'GAME_MODE')
      stats['GAME_TYPE'] = extract_value(json_output, 'GAME_TYPE')
      
      # Extract items (ITEM0 through ITEM6)
      (0..6).each do |i|
        item_value = extract_value(json_output, "ITEM#{i}")
        stats["ITEM#{i}"] = item_value
        Rails.logger.info "ITEM#{i}: #{item_value}" if item_value
      end
      stats['ITEMS_PURCHASED'] = extract_value(json_output, 'ITEMS_PURCHASED')
      
      # Debug: Let's also try a different pattern for items
      Rails.logger.info "Raw JSON output sample: #{json_output[0..500]}..."
      
      # Try alternative extraction patterns for items
      (0..6).each do |i|
        # Try without escaped quotes
        alt_match = json_output.match(/"ITEM#{i}":"([^"]*)"/)
        if alt_match && alt_match[1] != '0' && alt_match[1] != ''
          Rails.logger.info "Alternative ITEM#{i}: #{alt_match[1]}"
          stats["ITEM#{i}"] = alt_match[1] unless stats["ITEM#{i}"]
        end
        
        # Try with numbers (no quotes around value)
        num_match = json_output.match(/"ITEM#{i}":(\d+)/)
        if num_match && num_match[1] != '0'
          Rails.logger.info "Numeric ITEM#{i}: #{num_match[1]}"
          stats["ITEM#{i}"] = num_match[1] unless stats["ITEM#{i}"]
        end
      end
      
      stats.any? { |k, v| v } ? stats : nil
    rescue => e
      Rails.logger.error "Error extracting game statistics: #{e.message}"
      nil
    end
  end
  
  def select_main_player(all_players)
    return {} if all_players.empty?
    
    # Method 1: In ROFL files, the replay owner is typically the FIRST player in the JSON data
    # This is because ROFL files are generated from the perspective of one player
    
    # Method 2: Look for the player with the most complete statistical data
    # The replay owner often has more detailed stats recorded
    
    # Multiple methods to identify replay owner
    
    # Method 1: Look for players with specific detailed statistics that indicate replay ownership
    # In ROFL files, the replay owner often has more detailed or accurate data
    
    # Method 2: Check for players with complete item builds (6+ items)
    # Replay owners typically have full item data recorded
    
    # Method 3: Look for players with highest statistical values (they played the full game)
    
    scored_players = all_players.map.with_index do |player, index|
      ownership_score = 0
      
      # Basic data completeness (lower weight)
      ownership_score += 1 if player['RIOT_ID_GAME_NAME'] && !player['RIOT_ID_GAME_NAME'].empty?
      ownership_score += 1 if player['RIOT_ID_TAG_LINE'] && !player['RIOT_ID_TAG_LINE'].empty?
      
      # Game performance indicators (higher weight for active players)
      gold = player['GOLD_EARNED'].to_i
      kills = player['CHAMPIONS_KILLED'].to_i
      deaths = player['NUM_DEATHS'].to_i
      assists = player['ASSISTS'].to_i
      cs = player['MINIONS_KILLED'].to_i
      damage = player['TOTAL_DAMAGE_DEALT_TO_CHAMPIONS'].to_i
      vision = player['VISION_SCORE'].to_i
      
      # High engagement scores (active players more likely to be replay owner)
      ownership_score += 3 if gold > 10000  # Significant gold earned
      ownership_score += 2 if (kills + assists) > 5  # Active in fights
      ownership_score += 2 if cs > 100  # Farmed significantly
      ownership_score += 2 if damage > 15000  # Dealt significant damage
      ownership_score += 1 if vision > 20  # Good vision control
      ownership_score -= 1 if deaths > 10  # Penalize excessive deaths (less likely to be replay owner)
      
      # Item completeness (strong indicator)
      items = (0..6).map { |i| player["ITEM#{i}"] }.compact.reject { |item| item == '0' || item.empty? }
      ownership_score += items.length * 1.5  # Each item adds significant weight
      ownership_score += 5 if items.length >= 6  # Full build bonus
      
      # Position in array (replay owner is often not first, but could be anywhere)
      # No position-based scoring to avoid bias
      
      { player: player, score: ownership_score, index: index }
    end
    
    # Sort by completeness score (highest first)
    scored_players.sort_by! { |p| -p[:score] }
    
    # Log scoring for debugging
    Rails.logger.info "Player ownership scores (higher = more likely to be replay owner):"
    scored_players.each_with_index do |scored, rank|
      player = scored[:player]
      score = scored[:score]
      original_index = scored[:index]
      name = "#{player['RIOT_ID_GAME_NAME']}##{player['RIOT_ID_TAG_LINE']}"
      champion = player['SKIN']
      gold = player['GOLD_EARNED'].to_i
      items = (0..6).map { |i| player["ITEM#{i}"] }.compact.reject { |item| item == '0' || item.empty? }
      Rails.logger.info "  #{rank + 1}. #{name} (#{champion}) - Score: #{score} [Gold: #{gold}, Items: #{items.length}, Original pos: #{original_index + 1}]"
    end
    
    # Select the player with the highest completeness score
    if scored_players.any?
      selected_player = scored_players.first[:player]
      Rails.logger.info "Selected player with highest completeness score: #{selected_player['RIOT_ID_GAME_NAME']}##{selected_player['RIOT_ID_TAG_LINE']} playing #{selected_player['SKIN']}"
      return selected_player
    end
    
    # Fallback: Use first player
    default_player = all_players.first || {}
    if default_player['RIOT_ID_GAME_NAME']
      Rails.logger.warn "Defaulting to first player: #{default_player['RIOT_ID_GAME_NAME']}##{default_player['RIOT_ID_TAG_LINE']} playing #{default_player['SKIN']}"
    end
    
    default_player
  end
  
  def find_player_by_name(all_players, summoner_name, summoner_tag = nil)
    # Find a specific player by their summoner name and tag
    all_players.find do |player|
      player_name = player['RIOT_ID_GAME_NAME']
      player_tag = player['RIOT_ID_TAG_LINE']
      
      if summoner_tag
        player_name == summoner_name && player_tag == summoner_tag
      else
        player_name == summoner_name
      end
    end
  end

  def extract_player_stats_from_line(line)
    # Extract player statistics from a single JSON line
    stats = {}
    
    # Extract all the key stats we need
    stats['SKIN'] = extract_value(line, 'SKIN')
    stats['RIOT_ID_GAME_NAME'] = extract_value(line, 'RIOT_ID_GAME_NAME')
    stats['RIOT_ID_TAG_LINE'] = extract_value(line, 'RIOT_ID_TAG_LINE')
    stats['CHAMPIONS_KILLED'] = extract_value(line, 'CHAMPIONS_KILLED')
    stats['NUM_DEATHS'] = extract_value(line, 'NUM_DEATHS')
    stats['ASSISTS'] = extract_value(line, 'ASSISTS')
    stats['GOLD_EARNED'] = extract_value(line, 'GOLD_EARNED')
    stats['MINIONS_KILLED'] = extract_value(line, 'MINIONS_KILLED')
    stats['VISION_SCORE'] = extract_value(line, 'VISION_SCORE')
    stats['TOTAL_DAMAGE_DEALT_TO_CHAMPIONS'] = extract_value(line, 'TOTAL_DAMAGE_DEALT_TO_CHAMPIONS')
    stats['WIN'] = extract_value(line, 'WIN')
    stats['LEVEL'] = extract_value(line, 'LEVEL')
    stats['INDIVIDUAL_POSITION'] = extract_value(line, 'INDIVIDUAL_POSITION')
    stats['TEAM'] = extract_value(line, 'TEAM')
    
    # Extract items (ITEM0 through ITEM6)
    (0..6).each do |i|
      stats["ITEM#{i}"] = extract_value(line, "ITEM#{i}")
    end
    stats['ITEMS_PURCHASED'] = extract_value(line, 'ITEMS_PURCHASED')
    
    # Only return if we found meaningful data (at least champion name)
    stats['SKIN'] ? stats : {}
  end
  
  def extract_value(text, key)
    # Handle escaped quotes in JSON
    match = text.match(/\\"#{key}\\":\\"([^\\"]*)\\"/)
    match ? match[1] : nil
  end
  
  def extract_team_data(content)
    begin
      # Extract all player data blocks from the ROFL file
      json_output = `strings "#{@file_path}" | grep -E 'RIOT_ID_GAME_NAME|SKIN|TEAM.*WIN.*LEVEL'`
      
      return { players: [], teams: [] } if json_output.empty?
      
      # Find all complete player data blocks
      player_blocks = `strings "#{@file_path}" | grep -A200 -B200 'RIOT_ID_GAME_NAME'`
      
      players = []
      teams = { '100' => [], '200' => [] }
      
      # Extract individual player stats from each block
      player_blocks.scan(/\{[^}]*RIOT_ID_GAME_NAME[^}]*\}/).each do |block|
        player_data = extract_player_from_block(block)
        if player_data && player_data[:summoner_name] && player_data[:summoner_name] != ''
          players << player_data
          team_id = player_data[:team].to_s
          teams[team_id] << player_data if teams[team_id]
        end
      end
      
      {
        players: players,
        teams: {
          blue_team: teams['100'] || [],
          red_team: teams['200'] || []
        }
      }
    rescue => e
      Rails.logger.error "Error extracting team data: #{e.message}"
      { players: [], teams: [] }
    end
  end
  
  def extract_player_from_block(block)
    {
      summoner_name: extract_value(block, 'RIOT_ID_GAME_NAME'),
      summoner_tag: extract_value(block, 'RIOT_ID_TAG_LINE'),
      champion: extract_value(block, 'SKIN'),
      level: extract_value(block, 'LEVEL')&.to_i,
      kills: extract_value(block, 'CHAMPIONS_KILLED')&.to_i || 0,
      deaths: extract_value(block, 'NUM_DEATHS')&.to_i || 0,
      assists: extract_value(block, 'ASSISTS')&.to_i || 0,
      gold_earned: extract_value(block, 'GOLD_EARNED')&.to_i || 0,
      cs: extract_value(block, 'MINIONS_KILLED')&.to_i || 0,
      vision_score: extract_value(block, 'VISION_SCORE')&.to_i || 0,
      damage_dealt: extract_value(block, 'TOTAL_DAMAGE_DEALT_TO_CHAMPIONS')&.to_i || 0,
      position: extract_value(block, 'INDIVIDUAL_POSITION') || extract_value(block, 'TEAM_POSITION'),
      team: extract_value(block, 'TEAM')&.to_i,
      win: extract_value(block, 'WIN') == 'Win'
    }
  end
  
  def fix_json_string(json_str)
    # Try to fix common JSON formatting issues
    begin
      # Remove any trailing characters that might break JSON
      json_str = json_str.strip
      
      # Ensure it ends with a closing brace
      unless json_str.end_with?('}')
        # Find the last complete key-value pair and close there
        last_quote = json_str.rindex('"')
        if last_quote
          # Find the end of the value after the last quote
          value_end = json_str.index(/[,}]/, last_quote + 1)
          if value_end
            json_str = json_str[0...value_end] + '}'
          end
        end
      end
      
      JSON.parse(json_str)
      json_str
    rescue JSON::ParserError
      nil
    end
  end

  def self.extract_game_info(parsed_data)
    return {} unless parsed_data[:success] && parsed_data[:metadata]
    
    metadata = parsed_data[:metadata]
    filename = parsed_data[:original_filename] || parsed_data[:file_info][:name]
    
    # Extract from filename
    region = nil
    game_id_from_filename = nil
    if filename =~ /^([A-Z0-9]+)-([0-9]+)\.rofl$/i
      region = $1
      game_id_from_filename = $2
    end
    
    # Extract precise game duration from TIME_PLAYED (in seconds)
    time_played = metadata['TIME_PLAYED']&.to_i
    
    # Extract other detailed game information
    {
      game_id: game_id_from_filename || metadata['ID'] || "rofl_#{SecureRandom.hex(8)}",
      game_duration: time_played, # Exact duration in seconds
      game_version: metadata['GAME_VERSION'] || extract_version_from_filename(parsed_data[:file_info][:name]),
      game_mode: metadata['GAME_MODE'] || determine_game_mode(metadata),
      map_id: 11, # Summoner's Rift
      queue_id: metadata['QUEUE_ID']&.to_i || determine_queue_type(metadata),
      region: region,
      champion_name: metadata['SKIN'] || 'Unknown',
      champion_image_url: get_champion_image_url(metadata['SKIN'] || 'Unknown'),
      summoner_name: metadata['RIOT_ID_GAME_NAME'] || '',
      summoner_tag: metadata['RIOT_ID_TAG_LINE'] || '',
      level: metadata['LEVEL']&.to_i,
      kills: metadata['CHAMPIONS_KILLED']&.to_i || 0,
      deaths: metadata['NUM_DEATHS']&.to_i || 0,
      assists: metadata['ASSISTS']&.to_i || 0,
      gold_earned: metadata['GOLD_EARNED']&.to_i || 0,
      cs: metadata['MINIONS_KILLED']&.to_i || 0,
      vision_score: metadata['VISION_SCORE']&.to_i || 0,
      damage_dealt: metadata['TOTAL_DAMAGE_DEALT_TO_CHAMPIONS']&.to_i || 0,
      win: metadata['WIN'] == 'Win',
      team: metadata['TEAM']&.to_i,
      position: metadata['INDIVIDUAL_POSITION'] || metadata['TEAM_POSITION'],
      items: extract_items(metadata),
      items_purchased: metadata['ITEMS_PURCHASED']&.to_i || 0,
      timestamp: (File.mtime(parsed_data[:file_info][:full_path]) rescue Time.current),
      team_data: parsed_data[:team_data] || { players: [], teams: { blue_team: [], red_team: [] } }
    }
  end

  private

  def self.extract_version_from_filename(filename)
    # ROFL files don't store version in the JSON metadata
    # Version is in the binary header which is complex to parse
    # Using current patch version as reasonable default
    get_current_league_version
  end
  
  def self.get_current_league_version
    # You could fetch this dynamically from Riot's API:
    # https://ddragon.leagueoflegends.com/api/versions.json
    # For now, using a recent version
    "15.1.1" # Update this when new patches release
  end

  def self.determine_game_mode(metadata)
    # Determine game mode based on available metadata
    if metadata['GAME_ENDED_IN_SURRENDER'] == '1'
      'Classic (Surrender)'
    elsif metadata['GAME_ENDED_IN_EARLY_SURRENDER'] == '1'
      'Classic (Early Surrender)'
    else
      'Classic'
    end
  end

  def self.determine_queue_type(metadata)
    # Try to determine queue type from metadata
    # Common queue IDs:
    # 420 = Ranked Solo/Duo
    # 440 = Ranked Flex
    # 400 = Normal Draft
    # 430 = Normal Blind
    # 450 = ARAM
    
    # If we have position data, it's likely ranked
    if metadata['INDIVIDUAL_POSITION'] && metadata['INDIVIDUAL_POSITION'] != ''
      return 420 # Ranked Solo/Duo (most common)
    end
    
    # Default to normal draft if no clear indicators
    400
  end
  
  def self.extract_items(metadata)
    items = []
    (0..6).each do |i|
      item_id = metadata["ITEM#{i}"]
      if item_id && item_id != '0' && item_id != ''
        items << {
          slot: i,
          item_id: item_id.to_i,
          name: get_item_name(item_id.to_i),
          image_url: get_item_image_url(item_id.to_i)
        }
      end
    end
    items
  end
  
  def self.get_item_name(item_id)
    # Basic item mapping - in a real app, you'd have a complete item database
    item_names = {
      # Boots
      3020 => "Sorcerer's Shoes",
      3047 => "Plated Steelcaps",
      3046 => "Phantom Dancer",
      3078 => "Trinity Force",
      3172 => "Zephyr (Legacy Item)",
      
      # Consumables & Wards
      3340 => "Stealth Ward",
      2031 => "Refillable Potion",
      2003 => "Health Potion",
      
      # Components
      1058 => "Needlessly Large Rod",
      1052 => "Amplifying Tome",
      1055 => "Doran's Blade",
      1036 => "Long Sword",
      1033 => "Null-Magic Mantle",
      
      # Legendary Items
      3871 => "Bloodmail",
      4646 => "Stormsurge",
      6655 => "Luden's Companion",
      3033 => "Mortal Reminder",
      3031 => "Infinity Edge",
      3094 => "Rapid Firecannon",
      6672 => "Kraken Slayer",
      
      # Mythic/Legendary
      6632 => "Divine Sunderer",
      4005 => "Imperial Mandate",
      3153 => "Blade of the Ruined King"
    }
    
    item_names[item_id] || "Item ##{item_id}"
  end
  
  def self.get_champion_image_url(champion_name)
    # Riot's Data Dragon CDN for champion images
    # Using the latest version - you could make this dynamic by fetching versions.json
    version = "15.14.1" # Update this periodically or fetch dynamically
    "https://ddragon.leagueoflegends.com/cdn/#{version}/img/champion/#{champion_name}.png"
  end
  
  def self.get_item_image_url(item_id)
    # Handle legacy items that don't exist in current patch
    legacy_items = {
      3172 => "14.24.1" # Zephyr was removed after this patch
    }
    
    # Use legacy version for removed items, current version for others
    version = legacy_items[item_id.to_i] || "15.14.1"
    "https://ddragon.leagueoflegends.com/cdn/#{version}/img/item/#{item_id}.png"
  end
  
  public
  
  # Extract items from player data
  def extract_items_from_player_data(player_data)
    items = []
    (0..6).each do |i|
      item_id = player_data["ITEM#{i}"]
      if item_id && item_id != "0" && !item_id.empty?
        items << {
          slot: i,
          item_id: item_id,
          name: AccurateRoflParser.get_item_name(item_id.to_i),
          image_url: "https://ddragon.leagueoflegends.com/cdn/15.14.1/img/item/#{item_id}.png"
        }
      end
    end
    items
  end
  

  

end
