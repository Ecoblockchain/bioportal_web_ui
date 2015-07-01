# config valid only for Capistrano 3.1
lock '3.1.0'

set :application, 'bioportal_web_ui'
set :deploy_user, 'deployer'

set :repo_url, "git@github.com:ncbo/#{fetch(:application)}.git"

#set :deploy_via, :remote_cache

# Default branch is :master
# ask :branch, proc { `git rev-parse --abbrev-ref HEAD`.chomp }
NCBO_BRANCH = ENV.include?('NCBO_BRANCH') ? ENV['NCBO_BRANCH'] : 'staging'
set :branch, "#{NCBO_BRANCH}"

DEPLOY_TARGET =  ENV.include?('DEPLOY_TARGET') ? ENV['DEPLOY_TARGET'] : 'stageV4'

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
set :linked_files, %w{config/bioportal_config.rb config/database.yml public/robots.txt}

# Default value for linked_dirs is []
set :linked_dirs, %w{bin log tmp/pids tmp/cache vendor/bundle public/system}

# Default value for default_env is {}
# set :default_env, { path: "/opt/ruby/bin:$PATH" }

# Default value for keep_releases is 5
set :keep_releases, 5
set :bundle_flags, '--deployment' 
namespace :deploy do

  desc 'Incorporate the bioportal_conf private repository content'
  #Get cofiguration from repo if ENV NCBO_CONFIG_REPO is set 
  #(should be set to NCBO private config repo)
  task :get_config do
    if ENV.include?('NCBO_CONFIG_REPO') 
       PRIVATE_REPO = ENV['NCBO_CONFIG_REPO'] 
       CONFIG_PATH = "/tmp/#{SecureRandom.hex(15)}"
       on roles(:web) do
          execute "git clone -q #{PRIVATE_REPO} #{CONFIG_PATH}"
          execute "rsync -av #{CONFIG_PATH}/#{fetch(:application)}/ #{fetch(:deploy_to)}/shared"
          execute "rm -rf #{CONFIG_PATH}"
      end
    ## Modify the bioportal_config.rb file for DEPLOY_TARGET on the remote system
    cfg_file = File.join(release_path, "config", "bioportal_config.rb")
    sed_cmd = "\'s/^deploy_target =.*/deploy_target = \"#{DEPLOY_TARGET}\"/\'"
    run "sed -i -e #{sed_cmd} #{cfg_file}"
    end
  end

  desc 'Restart application'
  task :restart do
    on roles(:app), in: :sequence, wait: 5 do
      # Your restart mechanism here, for example:
      execute :touch, release_path.join('tmp/restart.txt')
    end
  end

  before :started, :get_config
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
