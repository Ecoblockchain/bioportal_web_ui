# config valid only for Capistrano 3.1
lock '3.4.1'

set :application, 'bioportal_web_ui'

set :repo_url, "git@github.com:ncbo/#{fetch(:application)}.git"

#set :deploy_via, :remote_cache

# Default branch is :master
# ask :branch, proc { `git rev-parse --abbrev-ref HEAD`.chomp }

# Default deploy_to directory is /var/www/my_app
set :deploy_to, "/srv/rails/#{fetch(:application)}"

# Default value for :scm is :git
# set :scm, :git

# Default value for :format is :pretty
# set :format, :pretty

# Default value for :log_level is :debug
# set :log_level, :debug

# Default value for :pty is false
# set :pty, true

# Default value for :linked_files is []
#set :linked_files, %w{config/bioportal_config.rb config/database.yml public/robots.txt config/newrelic.yml}

# Default value for linked_dirs is []
#set :linked_dirs, %w{bin log tmp/pids tmp/cache public/system public/assets config/locales}
set :linked_dirs, %w{bin log tmp/pids tmp/cache public/system public/assets}

# Default value for default_env is {}
# set :default_env, { path: "/opt/ruby/bin:$PATH" }

# Default value for keep_releases is 5
set :keep_releases, 5
set :bundle_flags, '--without development test --deployment' 

#If you want to restart using `touch tmp/restart.txt`, add this to your config/deploy.rb:

set :passenger_restart_with_touch, true
#If you want to restart using `passenger-config restart-app`, add this to your config/deploy.rb:
#set :passenger_restart_with_touch, false # Note that `nil` is NOT the same as `false` here
#If you don't set `:passenger_restart_with_touch`, capistrano-passenger will check what version of passenger you are running
#and use `passenger-config restart-app` if it is available in that version.

namespace :deploy do

  desc 'Incorporate the bioportal_conf private repository content'
  #Get cofiguration from repo if PRIVATE_CONFIG_REPO is set 
  #(should be set to NCBO private config repo)
  task :get_config do
     if defined?(PRIVATE_CONFIG_REPO)
       TMP_CONFIG_PATH = "/tmp/#{SecureRandom.hex(15)}"
       on roles(:web) do
          execute "git clone -q #{PRIVATE_CONFIG_REPO} #{TMP_CONFIG_PATH}"
          execute "rsync -av #{TMP_CONFIG_PATH}/#{fetch(:application)}/ #{release_path}/"
          execute "rm -rf #{TMP_CONFIG_PATH}"
      end
    end
  end

  desc 'Restart application'
  task :restart do
    on roles(:web), in: :sequence, wait: 5 do
      # Your restart mechanism here, for example:
      execute :touch, release_path.join('tmp/restart.txt')
    end
  end

  #before :started, :get_config
  after :updating, :get_config
  after :publishing, :restart

  after :restart, :clear_cache do
    on roles(:web), in: :groups, limit: 3, wait: 10 do
      # Here we can do anything such as:
      # within release_path do
      #   execute :rake, 'cache:clear'
      # end
    end
  end


end
