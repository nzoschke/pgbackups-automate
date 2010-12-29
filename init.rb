require "pgbackups/client"

module PGBackups
  class Client
    def get_user
      resource = authenticated_resource("/client/user")
      JSON.parse resource.get.body
    end

    def update_user(backup_url, backup_name)
      resource = authenticated_resource("/client/user")
      params = {:backup_url => backup_url, :backup_name => backup_name}
      resource.put(params)
    end
  end
end

module Heroku::Command
  class Pgbackups
    def index
      user # pre-fetch
      backups = []
      transfers.each { |t|
        next unless t['to_name'] =~ /BACKUP/ && !t['error_at'] && !t['destroyed_at']
        backups << [backup_name(t['to_url']), t['created_at'], t['size'], t['from_name'], ]
      }

      if backups.empty?
        display("No backups. Capture one with `heroku pgbackups:capture`.")
      else
        display Display.new.render([["ID", "Backup Time", "Size", "Database"]], backups)
      end

      automatic_summary
    end

    def user
      @user ||= pgbackup_client.get_user
    end

    def transfers
      @transfers ||= pgbackup_client.get_transfers
    end

    def automatic_plan?
      ['hourly', 'daily'].include? user["plan"]
    end

    def automatic_summary(backup_name=nil)
      return unless automatic_plan?

      backup_name ||= user['backup_name']

      if backup_name.empty?
        display("Warning: no database configured to capture scheduled backups from. User `heroku pgbackups:automate` to configure.")
      end

      from_name, from_url = resolve_db_id(backup_name, :default => "DATABASE_URL")

      db_display = from_name
      db_display += " (DATABASE_URL)" if from_name != "DATABASE_URL" && config_vars[from_name] == config_vars["DATABASE_URL"]

      auto_transfers = transfers.select { |t| t["to_name"] =~ /SCHEDULED/ }
      last = auto_transfers.last["finished_at"] || "none yet"
      display("\nCapturing automatic backups from #{db_display}")
      display("Last automated backup captured: #{last}")

      # t = Time.new.getutc
      # t = Time.parse(auto_transfers.last["finished_at"]) unless auto_transfers.last["finished_at"].empty?
      # 
      # if user['plan'] == 'hourly'
      #   t = Time.utc(t.year, t.month, t.day, t.hour + 1, 0)
      # elsif user['plan'] == 'daily'
      #   t = Time.utc(t.year, t.month, t.day, 11, 0)
      # end
      # 
      # display("Next automated backup scheduled for approximately: #{t}")
    end

    def automate
      db_id = args.shift || "DATABASE_URL"
      from_name, from_url = resolve_db_id(db_id, :default => "DATABASE_URL")

      result = pgbackup_client.update_user(from_url, from_name)
      abort(" !    Error starting automatic backups") unless result

      automatic_summary(from_name)
    end
  end
end