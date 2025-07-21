require 'zlib'
require 'json'

class EnhancedRoflParser
  def initialize(file_path)
    @file_path = file_path
  end

  def parse
    begin
      File.open(@file_path, 'rb') do |file|
        # Read magic header
        magic = file.read(6)
        unless magic.start_with?('RIOT')
          return { success: false, error: "Invalid ROFL file format" }
        end

        # Try to find metadata by searching for compressed JSON
        metadata = find_metadata(file)
        
        if metadata
          {
            success: true,
            header: { magic: magic.force_encoding('UTF-8').encode('UTF-8', invalid: :replace, undef: :replace) },
            metadata: metadata,
            file_info: {
              size: File.size(@file_path),
              name: File.basename(@file_path),
              full_path: @file_path
            }
          }
        else
          {
            success: false,
            error: "Could not extract metadata",
            file_info: {
              size: File.size(@file_path),
              name: File.basename(@file_path),
              full_path: @file_path
            }
          }
        end
      end
    rescue => e
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

  def find_metadata(file)
    file.rewind
    content = file.read
    
    # Search for compressed JSON metadata
    # Look for zlib magic bytes (0x78 0x9C, 0x78 0x01, 0x78 0xDA, etc.)
    zlib_patterns = [0x789C, 0x7801, 0x78DA, 0x785E]
    
    zlib_patterns.each do |pattern|
      offset = 0
      while offset < content.length - 1000
        index = content.index([pattern].pack('n'), offset)
        break unless index
        
        begin
          # Try to decompress from this position
          compressed_data = content[index..-1]
          decompressed = Zlib::Inflate.inflate(compressed_data)
          
          # Check if it looks like game metadata JSON
          if decompressed.include?('gameLength') || decompressed.include?('participants')
            return JSON.parse(decompressed)
          end
        rescue
          # Continue searching
        end
        
        offset = index + 1
      end
    end
    
    # If zlib search fails, try looking for uncompressed JSON
    json_start = content.index('{"gameLength"')
    if json_start
      json_end = content.index('}', json_start + 1000) # Look for end within reasonable distance
      if json_end
        begin
          json_str = content[json_start..json_end]
          return JSON.parse(json_str)
        rescue
          # Continue
        end
      end
    end
    
    nil
  end

  def self.extract_game_info(parsed_data)
    return {} unless parsed_data[:success]
    
    metadata = parsed_data[:metadata]
    filename = parsed_data[:original_filename] || parsed_data[:file_info][:name]
    
    # Extract from filename
    region = nil
    game_id_from_filename = nil
    if filename =~ /^([A-Z0-9]+)-([0-9]+)\.rofl$/i
      region = $1
      game_id_from_filename = $2
    end
    
    # Extract from metadata if available
    game_length = metadata&.dig('gameLength')
    participants = metadata&.dig('participants') || []
    
    # Find the current player (usually the first one or marked somehow)
    current_player = participants.first
    
    {
      game_id: game_id_from_filename || metadata&.dig('gameId')&.to_s || "rofl_#{SecureRandom.hex(8)}",
      game_duration: game_length ? (game_length / 1000.0).round : nil, # Convert ms to seconds
      game_version: extract_version_from_rofl(parsed_data[:file_info][:full_path]),
      game_mode: metadata&.dig('gameMode') || "Classic",
      map_id: metadata&.dig('mapId') || 11,
      queue_id: metadata&.dig('queueId') || 420,
      region: region,
      current_player: current_player,
      champion_name: current_player&.dig('championName'),
      champion_id: current_player&.dig('championId'),
      summoner_name: current_player&.dig('summonerName'),
      players: participants.map { |p| extract_player_info(p) },
      teams: extract_team_info(participants),
      timestamp: (File.mtime(parsed_data[:file_info][:full_path]) rescue Time.current)
    }
  end

  def self.extract_version_from_rofl(file_path)
    begin
      File.open(file_path, 'rb') do |file|
        file.seek(6)
        data_chunk = file.read(200)
        return "Unknown" if data_chunk.nil?
        
        data_str = data_chunk.force_encoding('UTF-8').encode('UTF-8', invalid: :replace, undef: :replace)
        version_match = data_str.match(/(\d+\.\d+\.\d+\.\d+)/)
        return version_match[1] if version_match
        
        if data_chunk.include?('.')
          ascii_parts = data_chunk.scan(/[\d.]+/).select { |s| s.match?(/\d+\.\d+\.\d+\.\d+/) }
          return ascii_parts.first if ascii_parts.any?
        end
        
        return "Unknown"
      end
    rescue
      "Unknown"
    end
  end

  def self.extract_player_info(participant)
    {
      summoner_name: participant['summonerName'],
      champion_name: participant['championName'],
      champion_id: participant['championId'],
      team_id: participant['teamId'],
      spell1_id: participant['spell1Id'],
      spell2_id: participant['spell2Id']
    }
  end

  def self.extract_team_info(participants)
    teams = participants.group_by { |p| p['teamId'] }
    teams.map do |team_id, players|
      {
        team_id: team_id,
        players: players.map { |p| extract_player_info(p) }
      }
    end
  end
end
