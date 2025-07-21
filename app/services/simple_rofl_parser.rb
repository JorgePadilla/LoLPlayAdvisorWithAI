class SimpleRoflParser
  def initialize(file_path)
    @file_path = file_path
  end

  def parse
    begin
      File.open(@file_path, 'rb') do |file|
        # Read magic header (6 bytes)
        magic = file.read(6)
        return { success: false, error: "Invalid magic: #{magic.inspect}" } unless magic.start_with?('RIOT')
        
        # Read signature length (1 byte) and signature
        signature_length = file.read(1).unpack('C')[0]
        signature = file.read(signature_length)
        
        # Read the 7 header uint32 values (28 bytes total)
        header_data = file.read(28)
        return { success: false, error: "Could not read header data" } if header_data.nil? || header_data.length < 28
        
        header_values = header_data.unpack('L<7') # Explicitly read 7 little-endian uint32s
        
        header = {
          magic: magic.force_encoding('UTF-8').encode('UTF-8', invalid: :replace, undef: :replace),
          signature: signature.force_encoding('UTF-8').encode('UTF-8', invalid: :replace, undef: :replace),
          header_length: header_values[0],
          file_length: header_values[1],
          metadata_offset: header_values[2],
          metadata_length: header_values[3],
          payload_header_offset: header_values[4],
          payload_header_length: header_values[5],
          payload_offset: header_values[6]
        }
        
        # Try to read metadata
        metadata = {}
        if header[:metadata_length] > 0 && header[:metadata_offset] > 0
          begin
            file.seek(header[:metadata_offset])
            metadata_raw = file.read(header[:metadata_length])
            
            # Try to parse as JSON first (some files might not be compressed)
            begin
              metadata = JSON.parse(metadata_raw)
            rescue JSON::ParserError
              # Try decompression
              begin
                decompressed = Zlib::Inflate.inflate(metadata_raw)
                metadata = JSON.parse(decompressed)
              rescue => e
                metadata = { parse_error: "Could not parse metadata: #{e.message}" }
              end
            end
          rescue => e
            metadata = { read_error: "Could not read metadata: #{e.message}" }
          end
        end
        
        {
          success: true,
          header: header,
          metadata: metadata,
          file_info: {
            size: File.size(@file_path),
            name: File.basename(@file_path)
          }
        }
      end
    rescue => e
      {
        success: false,
        error: e.message,
        file_info: {
          size: File.exist?(@file_path) ? File.size(@file_path) : 0,
          name: File.basename(@file_path)
        }
      }
    end
  end
  
  def self.extract_game_info(parsed_data)
    return {} unless parsed_data[:success] && parsed_data[:metadata]
    
    metadata = parsed_data[:metadata]
    
    {
      game_id: metadata['gameId'] || metadata['matchId'],
      game_duration: metadata['gameDuration'] || metadata['gameLength'],
      game_version: metadata['gameVersion'],
      game_mode: metadata['gameMode'],
      map_id: metadata['mapId'],
      queue_id: metadata['queueId'],
      players: extract_player_info(metadata),
      teams: extract_team_info(metadata),
      timestamp: metadata['gameCreation'] || metadata['gameStartTime']
    }
  end

  def self.extract_player_info(metadata)
    return [] unless metadata['participants']
    
    metadata['participants'].map do |participant|
      {
        summoner_name: participant['summonerName'],
        champion_id: participant['championId'],
        champion_name: participant['championName'],
        team_id: participant['teamId'],
        position: participant['individualPosition'] || participant['role'],
        kills: participant['kills'],
        deaths: participant['deaths'],
        assists: participant['assists'],
        level: participant['champLevel'],
        gold_earned: participant['goldEarned'],
        total_damage: participant['totalDamageDealtToChampions']
      }
    end
  end

  def self.extract_team_info(metadata)
    return [] unless metadata['teams']
    
    metadata['teams'].map do |team|
      {
        team_id: team['teamId'],
        win: team['win'],
        first_blood: team['firstBlood'],
        first_tower: team['firstTower'],
        first_dragon: team['firstDragon'],
        first_baron: team['firstBaron'],
        tower_kills: team['towerKills'],
        dragon_kills: team['dragonKills'],
        baron_kills: team['baronKills']
      }
    end
  end
end
