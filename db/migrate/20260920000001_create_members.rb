class CreateMembers < ActiveRecord::Migration[8.1]
  def change
    create_table :members do |t|
      t.string :name, null: false
      t.string :email, null: false
      t.string :tier, null: false, default: "standard"
      t.timestamps
    end
    add_index :members, :email, unique: true
  end
end
