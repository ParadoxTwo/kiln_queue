class CreateKilns < ActiveRecord::Migration[8.1]
  def change
    create_table :kilns do |t|
      t.string :name, null: false
      t.integer :capacity_cm3, null: false
      t.integer :max_temperature_c, null: false
      t.timestamps
    end
    add_index :kilns, :name, unique: true
  end
end
