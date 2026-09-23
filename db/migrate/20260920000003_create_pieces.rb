class CreatePieces < ActiveRecord::Migration[8.1]
  def change
    create_table :pieces do |t|
      t.references :member, null: false, foreign_key: true
      t.string :title, null: false
      t.integer :height_mm, null: false
      t.integer :width_mm, null: false
      t.integer :depth_mm, null: false
      t.string :clay_body, null: false
      t.integer :glaze_temperature_c, null: false
      t.string :status, null: false, default: "submitted"
      t.timestamps
    end
    add_index :pieces, :status
  end
end
