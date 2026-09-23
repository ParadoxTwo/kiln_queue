class CreatePlacements < ActiveRecord::Migration[8.1]
  def change
    create_table :placements do |t|
      t.references :firing, null: false, foreign_key: true
      t.references :piece, null: false, foreign_key: true
      t.timestamps
    end
    add_index :placements, [ :firing_id, :piece_id ], unique: true
  end
end
