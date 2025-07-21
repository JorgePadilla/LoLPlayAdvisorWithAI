class RoflParser
  require 'bindata'
  require 'json'
  require 'zlib'

  # ROFL file structure based on Riot's format
  class RoflHeader < BinData::Record
    endian :little
    
    string :magic, length: 6
    uint8 :signature_length
    string :signature, length: :signature_length
    uint32 :header_length
    uint32 :file_length
    uint32 :metadata_offset
    uint32 :metadata_length
    uint32 :payload_header_offset
    uint32 :payload_header_length
    uint32 :payload_offset
  end

  def initialize(file_path)
    @file_path = file_path
    @file = nil
  end

  def parse
    begin
      # Check if file exists and is readable
      unless File.exist?(@file_path) && File.readable?(@file_path)
        return {
          success: false,
          error: "File not found or not readable: #{@file_path}",
          file_info: {
            size: File.exist?(@file_path) ? File.size(@file_path) : 0,
            name: File.basename(@file_path)
          }
        }
      end
      
      @file = File.open(@file_path, 'rb')
      header = parse_header
      
      # Validate magic header
      unless header[:magic].start_with?('RIOT')
        return {
          success: false,
          error: "Invalid ROFL file format. Magic header: #{header[:magic].inspect}",
          file_info: {
            size: File.size(@file_path),
            name: File.basename(@file_path)
          }
        }
      end
      
      metadata = parse_metadata(header)
      payload_info = parse_payload_header(header)
      
      {
        success: true,
        header: header,
        metadata: metadata,
        payload_info: payload_info,
        file_info: {
          size: File.size(@file_path),
          name: File.basename(@file_path)
        }
      }
    rescue => e
      {
        success: false,
        error: e.message,
        file_info: {
          size: File.size(@file_path),
          name: File.basename(@file_path)
        }
      }
    ensure
      @file&.close
    end
  end

  private

  def parse_header
    @file.seek(0)
    
    # Read header manually for better error handling
    magic = @file.read(6)
    signature_length = @file.read(1).unpack('C')[0]
    signature = @file.read(signature_length)
    
    header_data = @file.read(32) # Read the rest of the header
    header_values = header_data.unpack('L<*') # Little-endian unsigned 32-bit integers
    
    {
      magic: magic,
      signature_length: signature_length,
      signature: signature,
      header_length: header_values[0],
      file_length: header_values[1],
      metadata_offset: header_values[2],
      metadata_length: header_values[3],
      payload_header_offset: header_values[4],
      payload_header_length: header_values[5],
      payload_offset: header_values[6]
    }
  end

  def parse_metadata(header)
    return {} if header[:metadata_length] == 0
    
    @file.seek(header[:metadata_offset])
    compressed_data = @file.read(header[:metadata_length])
    
    begin
      # Try to decompress with zlib
      decompressed = Zlib::Inflate.inflate(compressed_data)
      JSON.parse(decompressed)
    rescue Zlib::Error, JSON::ParserError => e
      # If decompression fails, try to parse as raw JSON
      begin
        JSON.parse(compressed_data)
      rescue JSON::ParserError
        { error: "Failed to parse metadata: #{e.message}" }
      end
    end
  end

  def parse_payload_header(header)
    return {} if header[:payload_header_length] == 0
    
    @file.seek(header[:payload_header_offset])
    payload_header_data = @file.read(header[:payload_header_length])
    
    begin
      # Try to decompress and parse payload header
      decompressed = Zlib::Inflate.inflate(payload_header_data)
      JSON.parse(decompressed)
    rescue Zlib::Error, JSON::ParserError => e
      begin
        JSON.parse(payload_header_data)
      rescue JSON::ParserError
        { error: "Failed to parse payload header: #{e.message}" }
      end
    end
  end

  def header_to_hash(header)
    {
      magic: header.magic,
      signature_length: header.signature_length,
      signature: header.signature,
      header_length: header.header_length,
      file_length: header.file_length,
      metadata_offset: header.metadata_offset,
      metadata_length: header.metadata_length,
      payload_header_offset: header.payload_header_offset,
      payload_header_length: header.payload_header_length,
      payload_offset: header.payload_offset
    }
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
