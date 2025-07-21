class CreateReplays < ActiveRecord::Migration[8.0]
  def change
    create_table :replays do |t|
      t.string :filename
      t.string :file_path
      t.integer :file_size
      t.string :game_id
      t.integer :game_duration
      t.string :game_version
      t.boolean :processed
      t.datetime :processed_at
      t.text :metadata

      t.timestamps
    end
  end
end
