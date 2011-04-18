require "pgbackups/client"

module PGBackups
  class Client
    def get_user
      resource = authenticated_resource("/client/user")
      OkJson.decode resource.get.body
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
    Heroku::Command::Help.group("pgbackups") do |group|
      group.command "pgbackups:automate [<DB_ID>]",               "begin capturing automatic backups for database ID (default: DATABASE_URL)"
    end

    def index
      user # pre-fetch
      backups = []
      transfers.each { |t|
        next unless t['to_name'] =~ /BACKUP/ && !t['error_at'] && !t['destroyed_at']
        backups << [backup_name(t['to_url']), t['created_at'], t['size'], t['from_name'], ]
      }

      if backups.empty?
        display("No backups. Capture one with `heroku pgbackups:capture`.")
        automatic_summary
      else
        display Display.new.render([["ID", "Backup Time", "Size", "Database"]], backups)
        display ""
        automatic_summary
      end
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
      from_name, from_url = resolve_db_id(backup_name, :default => "DATABASE_URL")
      auto_transfers = transfers.select { |t| t["to_name"] =~ /SCHEDULED/ }

      db_display = from_name
      db_display += " (DATABASE_URL)" if from_name != "DATABASE_URL" && config_vars[from_name] == config_vars["DATABASE_URL"]

      if backup_name
        display("Capturing automatic backups from #{db_display}")
        last = auto_transfers.empty? ? "None yet" : Time.parse(auto_transfers.last["finished_at"])
        current = auto_transfers.empty? ? Time.now : last
        if user['plan'] == 'hourly'
          nxt = Time.local(current.year, current.month, current.day, current.hour, 11)
          if nxt < current
            nxt = Time.local(current.year, current.month, current.day, current.hour + 1, 11)
          end
        elsif user['plan'] == 'daily'
          nxt = Time.local(current.year, current.month, current.day, 23, 0)
          if nxt < current
            nxt = Time.local(current.year, current.month, current.day + 1, 23, 0)
          end
        else
          nxt = "Unknown"
        end
      else
        display("Not capturing #{user['plan']} automatic backups. Use `heroku pgbackups:automate` to configure.")
        last = "Not configured"
        nxt = "Never"
      end

      last = last.strftime("%Y/%m/%d %H:%M %Z") if last.is_a? Time
      nxt = nxt.strftime("%Y/%m/%d %H:%M %Z") if nxt.is_a? Time
      display("Last automated backup captured: #{last}")
      display("Next automated backup scheduled for approximately: #{nxt}")
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
