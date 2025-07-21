class Replay < ApplicationRecord
  validates :filename, presence: true
  validates :file_path, presence: true, uniqueness: true
  validates :file_size, presence: true, numericality: { greater_than: 0 }
  
  scope :processed, -> { where(processed: true) }
  scope :unprocessed, -> { where(processed: false) }
  scope :recent, -> { order(created_at: :desc) }
  
  before_validation :set_defaults, on: :create
  after_create :process_replay_async
  
  def rofl_file?
    filename&.downcase&.end_with?('.rofl')
  end
  
  def file_exists?
    File.exist?(file_path) if file_path
  end
  
  def parsed_metadata
    return {} if metadata.blank?
    JSON.parse(metadata)
  rescue JSON::ParserError
    {}
  end
  
  def game_info
    parsed_metadata.dig('game_info') || {}
  end
  
  def players
    parsed_metadata.dig('team_data', 'players') || []
  end
  
  def teams
    Rails.logger.info "Teams Debug - parsed_metadata keys: #{parsed_metadata.keys}"
    Rails.logger.info "Teams Debug - team_data structure: #{parsed_metadata.dig('team_data')}"
    
    team_data = parsed_metadata.dig('team_data', 'teams') || []
    Rails.logger.info "Teams Debug - team_data: #{team_data.class} with #{team_data.is_a?(Array) ? team_data.length : team_data.keys} items"
    Rails.logger.info "Teams Debug - sample: #{team_data.is_a?(Hash) ? team_data.keys : team_data.first(2)}"
    
    # Handle both array and hash structures
    if team_data.is_a?(Hash)
      team_data
    else
      { blue_team: [], red_team: [] } # Default structure if teams is an array
    end
  end
  
  def blue_team
    teams_data = teams
    teams_data.dig('blue_team') || teams_data.dig(:blue_team) || []
  end
  
  def red_team
    teams_data = teams
    teams_data.dig('red_team') || teams_data.dig(:red_team) || []
  end
  
  def ai_analysis
    Rails.logger.info "AI Analysis Debug - processed?: #{processed?}"
    return nil unless processed?
    Rails.logger.info "AI Analysis Debug - Creating AiMatchAnalyzer"
    # Remove caching to ensure fresh analysis
    AiMatchAnalyzer.new(self).generate_analysis
  end
  
  def build_analysis
    return nil unless processed?
    # Temporarily disable caching to test new player detection
    ItemBuildAnalyzer.new(self).analyze_build
  end
  
  def reprocess!
    # Force reprocessing with new parser logic
    Rails.logger.info "Reprocessing replay #{id} with new parser logic"
    self.processed = false
    self.processed_at = nil
    self.metadata = nil
    self.save!
    process_replay!
  end


  
  def process_replay!
    return false unless file_exists? && rofl_file?
    
    # Try accurate parser first for precise game statistics
    accurate_parser = AccurateRoflParser.new(file_path)
    accurate_result = accurate_parser.parse
    
    if accurate_result[:success] && accurate_result[:game_info]
      # Accurate parser succeeded - use it
      accurate_result[:original_filename] = filename
      game_info = accurate_result[:game_info]  # Use the already-parsed game_info
      result = accurate_result
    else
      # Try enhanced parser as fallback
      enhanced_parser = EnhancedRoflParser.new(file_path)
      enhanced_result = enhanced_parser.parse
      
      if enhanced_result[:success] && enhanced_result[:metadata]
        enhanced_result[:original_filename] = filename
        game_info = EnhancedRoflParser.extract_game_info(enhanced_result)
        result = enhanced_result
      else
        # Fall back to basic parser
        parser = BasicRoflHandler.new(file_path)
        result = parser.parse
        result[:original_filename] = filename
        game_info = BasicRoflHandler.extract_game_info(result)
      end
    end
    
    if result[:success]
      update!(
        game_id: game_info[:game_id] || game_info['game_id'],
        game_duration: game_info[:game_duration] || game_info['game_duration'] || game_info[:duration] || game_info['duration'],
        game_version: game_info[:game_version] || game_info['game_version'],
        metadata: {
          header: result[:header],
          raw_metadata: result[:metadata],
          payload_info: result[:payload_info],
          game_info: game_info,
          players: (result[:team_data][:players] rescue []),
          teams: (result[:team_data][:teams] rescue []),
          team_data: result[:team_data] || { players: [], teams: { blue_team: [], red_team: [] } }
        }.to_json,
        processed: true,
        processed_at: Time.current
      )
      true
    else
      update!(metadata: { error: result[:error] }.to_json)
      false
    end
  end
  
  private
  
  def set_defaults
    self.processed = false if processed.nil?
    self.file_size = File.size(file_path) if file_path && File.exist?(file_path)
  end
  
  def process_replay_async
    # In a real app, you'd use a background job like Sidekiq
    # For now, we'll process synchronously
    process_replay! if rofl_file?
  end
end
