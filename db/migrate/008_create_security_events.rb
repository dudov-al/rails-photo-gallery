class CreateSecurityEvents < ActiveRecord::Migration[7.0]
  def change
    create_table :security_events do |t|
      t.string :event_type, null: false
      t.references :photographer, null: true, foreign_key: true
      t.string :ip_address, null: false
      t.string :session_id
      t.text :user_agent
      t.string :severity, default: 'MEDIUM', null: false
      t.json :additional_data
      t.datetime :occurred_at, null: false
      
      t.timestamps
    end
    
    add_index :security_events, :event_type
    add_index :security_events, :ip_address
    add_index :security_events, :occurred_at
    add_index :security_events, :severity
    add_index :security_events, [:ip_address, :event_type]
    add_index :security_events, [:photographer_id, :event_type]
    add_index :security_events, [:occurred_at, :event_type]
  end
end