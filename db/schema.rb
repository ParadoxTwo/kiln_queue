# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_20_000006) do
  create_table "charges", force: :cascade do |t|
    t.integer "amount_cents", null: false
    t.datetime "created_at", null: false
    t.string "description", null: false
    t.integer "member_id", null: false
    t.integer "piece_id", null: false
    t.datetime "updated_at", null: false
    t.index ["member_id"], name: "index_charges_on_member_id"
    t.index ["piece_id"], name: "index_charges_on_piece_id"
  end

  create_table "firings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "fired_at"
    t.integer "kiln_id", null: false
    t.string "kind", null: false
    t.date "scheduled_on", null: false
    t.string "status", default: "planned", null: false
    t.integer "target_temperature_c", null: false
    t.datetime "updated_at", null: false
    t.index ["kiln_id"], name: "index_firings_on_kiln_id"
    t.index ["status", "scheduled_on"], name: "index_firings_on_status_and_scheduled_on"
  end

  create_table "kilns", force: :cascade do |t|
    t.integer "capacity_cm3", null: false
    t.datetime "created_at", null: false
    t.integer "max_temperature_c", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_kilns_on_name", unique: true
  end

  create_table "members", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name", null: false
    t.string "tier", default: "standard", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_members_on_email", unique: true
  end

  create_table "pieces", force: :cascade do |t|
    t.string "clay_body", null: false
    t.datetime "created_at", null: false
    t.integer "depth_mm", null: false
    t.integer "glaze_temperature_c", null: false
    t.integer "height_mm", null: false
    t.integer "member_id", null: false
    t.string "status", default: "submitted", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "width_mm", null: false
    t.index ["member_id"], name: "index_pieces_on_member_id"
    t.index ["status"], name: "index_pieces_on_status"
  end

  create_table "placements", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "firing_id", null: false
    t.integer "piece_id", null: false
    t.datetime "updated_at", null: false
    t.index ["firing_id", "piece_id"], name: "index_placements_on_firing_id_and_piece_id", unique: true
    t.index ["firing_id"], name: "index_placements_on_firing_id"
    t.index ["piece_id"], name: "index_placements_on_piece_id"
  end

  add_foreign_key "charges", "members"
  add_foreign_key "charges", "pieces"
  add_foreign_key "firings", "kilns"
  add_foreign_key "pieces", "members"
  add_foreign_key "placements", "firings"
  add_foreign_key "placements", "pieces"
end
