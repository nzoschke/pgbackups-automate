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

module Heroku::Command
  class Pgbackups
    def automate
      db_id = args.shift || "DATABASE_URL"
      from_name, from_url = resolve_db_id(db_id, :default => "DATABASE_URL")

      result = pgbackup_client.update_user(from_url, from_name)
      abort(" !    Error starting automatic backups") unless result

      db_display = from_name
      db_display += " (DATABASE_URL)" if from_name != "DATABASE_URL" && config_vars[from_name] == config_vars["DATABASE_URL"]
      display("Capturing automatic backup from #{db_display}")
    end
  end
end