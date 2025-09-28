class ReplaysController < ApplicationController
  include ActionView::Helpers::NumberHelper
  before_action :set_replay, only: [:show, :destroy, :watch, :local_viewer]

  def index
    @replays = Replay.recent.limit(50)
    @processed_count = Replay.processed.count
    @total_count = Replay.count
  end

  def show
    @game_info = @replay.game_info
    @players = @replay.players
    @teams = @replay.teams
    @blue_team = @replay.blue_team
    @red_team = @replay.red_team
    @ai_analysis = @replay.ai_analysis
    @build_analysis = @replay.build_analysis

    # Debug logging
    Rails.logger.info "Controller Debug - @ai_analysis present: #{@ai_analysis.present?}"
    Rails.logger.info "Controller Debug - @ai_analysis keys: #{@ai_analysis&.keys}"
    Rails.logger.info "Controller Debug - @ai_analysis[:summary]: #{@ai_analysis&.dig(:summary)&.truncate(50)}"
    Rails.logger.info "Controller Debug - @blue_team count: #{@blue_team&.length}"
    Rails.logger.info "Controller Debug - @red_team count: #{@red_team&.length}"

    # Enhanced data for comprehensive analysis
    @timeline_data = extract_timeline_data
    @match_summary = extract_match_summary
    @player_highlights = extract_player_highlights
  end

  def new
    @replay = Replay.new
  end

  def create
    uploaded_file = params[:replay]&.[](:file)

    if uploaded_file.nil?
      flash[:error] = "Please select a file to upload"
      redirect_to new_replay_path and return
    end

    unless uploaded_file.original_filename.downcase.end_with?(".rofl")
      flash[:error] = "Please upload a valid .rofl file"
      redirect_to new_replay_path and return
    end

    # Create unique filename to avoid conflicts
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    filename = "#{timestamp}_#{uploaded_file.original_filename}"
    file_path = Rails.root.join("storage", "replays", filename)

    begin
      # Save the uploaded file
      File.open(file_path, "wb") do |file|
        file.write(uploaded_file.read)
      end

      # Create replay record
      @replay = Replay.create!(
        filename: uploaded_file.original_filename,
        file_path: file_path.to_s,
        file_size: File.size(file_path)
      )

      # Parse the replay automatically
      parser = AccurateRoflParser.new(@replay.file_path)
      result = parser.parse
      
      if result[:success]
        @replay.update!(
          metadata: result.to_json,
          processed: true,
          processed_at: Time.current
        )
        flash[:success] = "Replay uploaded and processed successfully!"
      else
        flash[:warning] = "Replay uploaded but processing failed. You can still view basic info."
      end
      
      redirect_to replay_path(@replay)

    rescue => e
      # Clean up file if record creation fails
      File.delete(file_path) if File.exist?(file_path)
      flash[:error] = "Failed to upload replay: #{e.message}"
      redirect_to new_replay_path
    end
  end

  def watch
    unless @replay.file_exists?
      flash[:error] = "Replay file not found"
      redirect_to replay_path(@replay) and return
    end

    begin
      # Try to open the ROFL file with the system's default application
      success = false

      if RbConfig::CONFIG["host_os"] =~ /darwin/i  # macOS
        success = system("open", @replay.file_path)
      elsif RbConfig::CONFIG["host_os"] =~ /linux/i  # Linux
        success = system("xdg-open", @replay.file_path)
      elsif RbConfig::CONFIG["host_os"] =~ /mswin|mingw|cygwin/i  # Windows
        success = system("start", @replay.file_path)
      end

      if success
        flash[:success] = "Opening replay in League of Legends client..."
      else
        flash[:warning] = "Could not open in LoL client. Try the local viewer below."
      end

      redirect_to replay_path(@replay)

    rescue => e
      flash[:error] = "Failed to open replay: #{e.message}. Try the local viewer below."
      redirect_to replay_path(@replay)
    end
  end

  def local_viewer
    unless @replay.file_exists?
      flash[:error] = "Replay file not found"
      redirect_to replay_path(@replay) and return
    end

    # Extract comprehensive match data for local viewing
    @timeline_data = extract_timeline_data
    @key_moments = extract_key_moments
    @match_summary = extract_match_summary
    @player_highlights = extract_player_highlights
  end

  def destroy
    # Delete the file
    File.delete(@replay.file_path) if @replay.file_exists?

    # Delete the record
    @replay.destroy

    flash[:success] = "Replay deleted successfully"
    redirect_to replays_path
  end
  


  private

  def set_replay
    @replay = Replay.find(params[:id])
  end

  def replay_params
    params.require(:replay).permit(:file)
  end

  def extract_timeline_data
    return {} unless @replay.parsed_metadata

    game_info = @replay.game_info
    duration = game_info[:game_duration] || 0

    {
      duration: duration,
      duration_formatted: format_duration(duration),
      phases: [
        { name: "Early Game", start: 0, end: [ duration * 0.25, 900 ].min, color: "bg-green-500" },
        { name: "Mid Game", start: [ duration * 0.25, 900 ].min, end: [ duration * 0.75, 1800 ].min, color: "bg-yellow-500" },
        { name: "Late Game", start: [ duration * 0.75, 1800 ].min, end: duration, color: "bg-red-500" }
      ]
    }
  end

  def extract_key_moments
    return [] unless @replay.parsed_metadata

    moments = []
    game_info = @replay.game_info
    duration = game_info[:game_duration] || 0

    # Game start
    moments << {
      time: 0,
      title: "🎮 Game Start",
      description: "Match begins",
      type: "start"
    }

    # First blood (estimated around 3-5 minutes)
    if duration > 180
      moments << {
        time: rand(180..300),
        title: "🩸 First Blood",
        description: "First kill of the game",
        type: "kill"
      }
    end

    # Mid game objectives (estimated)
    if duration > 900
      moments << {
        time: rand(900..1200),
        title: "🐉 Dragon Fight",
        description: "Team fight over dragon",
        type: "objective"
      }
    end

    if duration > 1200
      moments << {
        time: rand(1200..1500),
        title: "🏰 Baron Fight",
        description: "Team fight over Baron",
        type: "objective"
      }
    end

    # Game end
    moments << {
      time: duration,
      title: "🏆 Victory!",
      description: "Match ends in victory",
      type: "end"
    }

    moments.sort_by { |m| m[:time] }
  end

  def extract_match_summary
    game_info = @replay.game_info

    # Debug logging
    Rails.logger.info "Match Summary Debug - @blue_team: #{@blue_team&.length} players"
    Rails.logger.info "Match Summary Debug - @red_team: #{@red_team&.length} players"
    Rails.logger.info "Match Summary Debug - blue_team sample: #{@blue_team&.first&.slice('summoner_name', 'kills', 'deaths', 'assists')}"
    Rails.logger.info "Match Summary Debug - red_team sample: #{@red_team&.first&.slice('summoner_name', 'kills', 'deaths', 'assists')}"

    # Get user's team data (blue or red team based on user's team)
    user_team = @blue_team.any? ? @blue_team : @red_team
    enemy_team = @blue_team.any? ? @red_team : @blue_team

    # Calculate team totals
    team_kills = user_team.sum { |p| (p["kills"] || p[:kills] || 0).to_i }
    team_deaths = user_team.sum { |p| (p["deaths"] || p[:deaths] || 0).to_i }
    team_assists = user_team.sum { |p| (p["assists"] || p[:assists] || 0).to_i }
    team_gold = user_team.sum { |p| (p["gold_earned"] || p[:gold_earned] || 0).to_i }
    team_damage = user_team.sum { |p| (p["total_damage"] || p[:total_damage] || 0).to_i }

    enemy_kills = enemy_team.sum { |p| (p["kills"] || p[:kills] || 0).to_i }

    {
      team_kills: team_kills,
      team_deaths: team_deaths,
      team_assists: team_assists,
      team_gold: team_gold,
      team_damage: team_damage,
      enemy_kills: enemy_kills,
      kda_ratio: team_deaths > 0 ? ((team_kills + team_assists).to_f / team_deaths).round(2) : (team_kills + team_assists),
      match_result: determine_match_result(game_info, user_team),
      match_intensity: calculate_match_intensity(game_info, user_team + enemy_team)
    }
  end

  def extract_player_highlights
    # Focus on user's team for highlights
    user_team = @blue_team.any? ? @blue_team : @red_team
    return [] if user_team.empty?

    highlights = []

    # Best KDA on user's team
    best_kda_player = user_team.max_by do |p|
      kills = (p["kills"] || p[:kills] || 0).to_i
      deaths = [ (p["deaths"] || p[:deaths] || 1).to_i, 1 ].max
      assists = (p["assists"] || p[:assists] || 0).to_i
      (kills + assists) / deaths.to_f
    end

    if best_kda_player
      kills = (best_kda_player["kills"] || best_kda_player[:kills] || 0).to_i
      deaths = (best_kda_player["deaths"] || best_kda_player[:deaths] || 0).to_i
      assists = (best_kda_player["assists"] || best_kda_player[:assists] || 0).to_i
      kda = deaths > 0 ? ((kills + assists).to_f / deaths).round(2) : (kills + assists)

      highlights << {
        title: "🏆 Team Best KDA",
        player: best_kda_player["summoner_name"] || best_kda_player[:summoner_name],
        champion: best_kda_player["champion_name"] || best_kda_player[:champion_name],
        value: "#{kills}/#{deaths}/#{assists} (#{kda})",
        description: "Team MVP performance"
      }
    end

    # Most Gold on user's team
    richest_player = user_team.max_by { |p| (p["gold_earned"] || p[:gold_earned] || 0).to_i }
    if richest_player
      gold = (richest_player["gold_earned"] || richest_player[:gold_earned] || 0).to_i
      if gold > 0
        highlights << {
          title: "💰 Team Gold Leader",
          player: richest_player["summoner_name"] || richest_player[:summoner_name],
          champion: richest_player["champion_name"] || richest_player[:champion_name],
          value: "#{number_with_delimiter(gold)}g",
          description: "Economic powerhouse"
        }
      end
    end

    # Most Damage on user's team
    damage_dealer = user_team.max_by { |p| (p["total_damage"] || p[:total_damage] || 0).to_i }
    if damage_dealer
      damage = (damage_dealer["total_damage"] || damage_dealer[:total_damage] || 0).to_i
      if damage > 0
        highlights << {
          title: "⚔️ Team Damage Leader",
          player: damage_dealer["summoner_name"] || damage_dealer[:summoner_name],
          champion: damage_dealer["champion_name"] || damage_dealer[:champion_name],
          value: "#{number_with_delimiter(damage)}",
          description: "Carried team fights"
        }
      end
    end

    # User's personal performance (if identifiable)
    game_info = @replay.game_info
    user_summoner = game_info[:summoner_name]
    if user_summoner
      user_player = user_team.find { |p| (p["summoner_name"] || p[:summoner_name]) == user_summoner }
      if user_player
        kills = (user_player["kills"] || user_player[:kills] || 0).to_i
        deaths = (user_player["deaths"] || user_player[:deaths] || 0).to_i
        assists = (user_player["assists"] || user_player[:assists] || 0).to_i
        kda = deaths > 0 ? ((kills + assists).to_f / deaths).round(2) : (kills + assists)

        highlights << {
          title: "🎮 Your Performance",
          player: user_summoner,
          champion: user_player["champion_name"] || user_player[:champion_name],
          value: "#{kills}/#{deaths}/#{assists} (#{kda})",
          description: game_info[:result] == "Victory" ? "Victory achieved!" : "Good effort!"
        }
      end
    end

    highlights
  end

  def calculate_match_intensity(game_info, players)
    duration = game_info[:game_duration] || 1
    total_kills = players.sum { |p| p[:kills] || 0 }
    kills_per_minute = total_kills / (duration / 60.0)

    case kills_per_minute
    when 0..0.5
      { level: "Low", description: "Farming focused", color: "text-green-600" }
    when 0.5..1.0
      { level: "Medium", description: "Balanced gameplay", color: "text-yellow-600" }
    when 1.0..1.5
      { level: "High", description: "Action packed", color: "text-orange-600" }
    else
      { level: "Extreme", description: "Non-stop fighting", color: "text-red-600" }
    end
  end

  def determine_match_result(game_info, user_team)
    # Try multiple ways to determine if it's a victory
    # 1. Check game_info for result
    return game_info[:result] if game_info[:result] && game_info[:result] != 'Unknown'
    return game_info['result'] if game_info['result'] && game_info['result'] != 'Unknown'
    
    # 2. Check if user_team has win status
    if user_team.any?
      first_player = user_team.first
      win_status = first_player['win'] || first_player[:win]
      return win_status ? 'Victory' : 'Defeat' if !win_status.nil?
    end
    
    # 3. Check blue team vs red team (blue team typically wins if they have more data)
    if @blue_team.any? && @red_team.any?
      # If we have team data, check which team the user is on and their win status
      blue_wins = @blue_team.any? { |p| p['win'] || p[:win] }
      red_wins = @red_team.any? { |p| p['win'] || p[:win] }
      
      if blue_wins && !red_wins
        return user_team == @blue_team ? 'Victory' : 'Defeat'
      elsif red_wins && !blue_wins
        return user_team == @red_team ? 'Victory' : 'Defeat'
      end
    end
    
    # 4. Default fallback
    'Unknown'
  end
  
  def get_item_stats(item_id)
    item_stats = {
      3078 => ['+25 Attack Damage', '+700 Health', '+300 Mana', '+20 Ability Haste'], # Trinity Force
      3094 => ['+45% Attack Speed', '+20% Critical Strike Chance', '+7% Movement Speed'], # Rapid Firecannon
      3031 => ['+70 Attack Damage', '+20% Critical Strike Chance'], # Infinity Edge
      3036 => ['+40% Armor Penetration'], # Lord Dominik's Regards
      3033 => ['+60 Attack Damage', '+10% Cooldown Reduction'], # Mortal Reminder
      3142 => ['+55 Attack Damage', '+18 Lethality', '+15 Ability Haste'], # Youmuu's Ghostblade
      3153 => ['+40 Attack Damage', '+25% Attack Speed', '+12% Life Steal'], # Blade of the Ruined King
      3026 => ['+450 Health', '+40 Magic Resist', '+100% Base Health Regen'], # Guardian Angel
      3742 => ['+300 Health', '+30 Armor', '+200% Base Health Regen'], # Dead Man's Plate
      3065 => ['+425 Health', '+60 Magic Resist', '+100% Base Health Regen'], # Spirit Visage
      # Additional items from your build
      3172 => ['+50% Attack Speed', '+30% Critical Strike Chance', '+5% Movement Speed'], # Zephyr
      3046 => ['+25% Attack Speed', '+20% Critical Strike Chance', '+7% Movement Speed'], # Phantom Dancer
      2031 => ['2 Charges', 'Restores 125 Health over 12 seconds'], # Refillable Potion
      1055 => ['+8 Attack Damage', '+80 Health', '+3% Life Steal'], # Doran's Blade
      3340 => ['4 Stealth Wards', '90-120 second duration', 'Reveals area'], # Stealth Ward
    }
    item_stats[item_id.to_i] || []
  end
  
  def get_item_description(item_id)
    descriptions = {
      3078 => 'After using an ability, your next basic attack deals bonus damage and grants movement speed.',
      3094 => 'Energized attacks deal bonus magic damage and grant extended range.',
      3031 => 'Critical strikes deal significantly more damage.',
      3036 => 'Grants armor penetration based on bonus health difference.',
      3033 => 'Applies Grievous Wounds, reducing healing on enemies.',
      3142 => 'Grants movement speed and ghosting when activated.',
      3153 => 'Attacks deal current health damage and steal movement speed.',
      3026 => 'Upon taking lethal damage, revive with health and gain damage reduction.',
      3742 => 'Build momentum by moving, then discharge it on your next attack.',
      3065 => 'Increases all healing and shielding received.',
      # Additional items from your build
      3172 => 'Grants attack speed, critical strike chance, and movement speed. Provides tenacity.',
      3046 => 'Grants ghosting when moving. Spectral Waltz increases attack and movement speed.',
      2031 => 'Consumable item that can be refilled at the shop. Provides health regeneration.',
      1055 => 'Starting item that provides attack damage, health, and life steal for early game.',
      3340 => 'Trinket that places stealth wards to provide vision of an area.'
    }
    descriptions[item_id.to_i]
  end
  
  def get_item_cost(item_id)
    costs = {
      3078 => 3333, # Trinity Force
      3094 => 2600, # Rapid Firecannon
      3031 => 3400, # Infinity Edge
      3036 => 3000, # Lord Dominik's Regards
      3033 => 3000, # Mortal Reminder
      3142 => 2900, # Youmuu's Ghostblade
      3153 => 3200, # Blade of the Ruined King
      3026 => 2800, # Guardian Angel
      3742 => 2900, # Dead Man's Plate
      3065 => 2900, # Spirit Visage
      # Additional items from your build
      3172 => 2800, # Zephyr
      3046 => 2800, # Phantom Dancer
      2031 => 150,  # Refillable Potion
      1055 => 450,  # Doran's Blade
      3340 => 0     # Stealth Ward (Trinket)
    }
    costs[item_id.to_i]
  end
  
  def get_item_category(item_id)
    categories = {
      3078 => 'Damage/Tank Hybrid',
      3094 => 'Attack Speed/Crit',
      3031 => 'Critical Strike',
      3036 => 'Armor Penetration',
      3033 => 'Anti-Heal',
      3142 => 'Lethality/Mobility',
      3153 => 'Attack Speed/Sustain',
      3026 => 'Defensive/Revival',
      3742 => 'Tank/Mobility',
      3065 => 'Magic Resist/Sustain',
      # Additional items from your build
      3172 => 'Attack Speed/Tenacity',
      3046 => 'Attack Speed/Mobility',
      2031 => 'Consumable/Health',
      1055 => 'Starting Item',
      3340 => 'Vision/Trinket'
    }
    categories[item_id.to_i] || 'Unknown'
  end
  
  def get_item_tier(item_id)
    # Define item tiers more specifically
    legendary_items = [3078, 3094, 3031, 3036, 3033, 3142, 3153, 3026, 3742, 3065, 3172, 3046]
    basic_items = [1055] # Doran's items
    consumables = [2031] # Potions
    trinkets = [3340] # Wards
    
    case item_id.to_i
    when *legendary_items
      'Legendary'
    when *basic_items
      'Basic'
    when *consumables
      'Consumable'
    when *trinkets
      'Trinket'
    else
      'Epic/Component'
    end
  end
  
  def format_duration(seconds)
    minutes = seconds / 60
    remaining_seconds = seconds % 60
    "#{minutes}m #{remaining_seconds}s"
  end

  def extract_region_from_filename(filename)
    return nil unless filename

    # Common ROFL filename patterns:
    # NA1-1234567890.rofl
    # EUW1-1234567890.rofl
    # KR-1234567890.rofl
    # etc.

    if filename =~ /^([A-Z]{2,4}[0-9]*)-([0-9]+)\.rofl$/i
      region_code = $1

      # Map region codes to full names
      region_map = {
        'NA1' => 'North America',
        'EUW1' => 'Europe West',
        'EUNE' => 'Europe Nordic & East',
        'KR' => 'Korea',
        'BR1' => 'Brazil',
        'LA1' => 'Latin America North',
        'LA2' => 'Latin America South',
        'OC1' => 'Oceania',
        'RU' => 'Russia',
        'TR1' => 'Turkey',
        'JP1' => 'Japan',
        'PBE1' => 'Public Beta Environment'
      }

      region_map[region_code.upcase] || region_code
    else
      nil
    end
  end

  def extract_patch_number(full_version)
    return nil unless full_version && full_version != 'Unknown'

    # Extract patch number from full version (e.g., "15.14.695.3589" -> "15.14")
    version_parts = full_version.split('.')
    if version_parts.length >= 2
      "#{version_parts[0]}.#{version_parts[1]}"
    else
      nil
    end
  end

  def extract_game_id_from_filename(filename)
    return nil unless filename

    # Common ROFL filename patterns:
    # NA1-1234567890.rofl
    # EUW1-1234567890.rofl
    # KR-1234567890.rofl
    # etc.

    if filename =~ /^([A-Z]{2,4}[0-9]*)-([0-9]+)\.rofl$/i
      $2 # Return the game ID part
    else
      nil
    end
  end

  helper_method :format_duration, :get_item_stats, :get_item_description, :get_item_cost, :get_item_category, :get_item_tier, :extract_region_from_filename, :extract_patch_number, :extract_game_id_from_filename
end
