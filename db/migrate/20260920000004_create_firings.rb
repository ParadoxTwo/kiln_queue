class CreateFirings < ActiveRecord::Migration[8.1]
  def change
    create_table :firings do |t|
      t.references :kiln, null: false, foreign_key: true
      t.string :kind, null: false
      t.date :scheduled_on, null: false
      t.integer :target_temperature_c, null: false
      t.string :status, null: false, default: "planned"
      t.datetime :fired_at
      t.timestamps
    end
    add_index :firings, [ :status, :scheduled_on ]
  end
end
