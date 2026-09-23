class CreateCharges < ActiveRecord::Migration[8.1]
  def change
    create_table :charges do |t|
      t.references :member, null: false, foreign_key: true
      t.references :piece, null: false, foreign_key: true
      t.integer :amount_cents, null: false
      t.string :description, null: false
      t.timestamps
    end
  end
end
