# -*- mode: ruby -*-
# vi: set ft=ruby :

# Load user variables
require 'yaml'

def find_base_dir(dir='.', fn='Vagrantfile')
  while true
    path = File.join dir, fn
    break if File.file? path or File.file?(File.join dir, 'Vagrantfile')
    dir = File.expand_path File.join dir, '..'
  end
  dir
end

def mkdir(dir)
  Dir.mkdir(dir) unless Dir.exists? dir
end

# Get base directory
base_dir = find_base_dir

# Load configuration
VARS = YAML.load(File.read(File.join base_dir, 'vars.yml'))

# Make directories needed for CMS site/DB persistence
mkdir(File.join base_dir, VARS['HOST_SHARE_DIR'], 'webroot')
mkdir(File.join base_dir, VARS['HOST_SHARE_DIR'], 'webroot', 'app')
mkdir(File.join base_dir, VARS['HOST_SHARE_DIR'], 'webroot', 'app', 'cache')
mkdir(File.join base_dir, VARS['HOST_SHARE_DIR'], 'webroot', 'app', 'site')
mkdir(File.join base_dir, VARS['HOST_SHARE_DIR'], 'webroot', 'app', 'site', 'resources')
mkdir(File.join base_dir, VARS['HOST_SHARE_DIR'], 'db')
mkdir(File.join base_dir, VARS['HOST_SHARE_DIR'], 'db', 'hub')
mkdir(File.join base_dir, VARS['HOST_SHARE_DIR'], 'db', 'hub_metrics')

FORWARDS = [
  # SSH is auto-forwarded to host port 2222 or similar
  { id: 'http', guest: 80, host: VARS['HOST_PORT_HTTP'].to_i },
  { id: 'https', guest: 443, host: VARS['HOST_PORT_HTTPS'].to_i },
  { id: 'mysql', guest: 3306, host: VARS['HOST_PORT_MYSQL'].to_i },
  { id: 'wss', guest: 8443, host: VARS['HOST_PORT_WSS'].to_i },
]

if VARS['SOLR_ENABLED']
  FORWARDS << { id: 'solr', guest: 8445, host: VARS['HOST_PORT_SOLR'].to_i }
end

Vagrant.configure('2') do |config|
  config.vm.box = VARS['HUBZERO_VAGRANT_BOX']

  config.vm.hostname = "#{VARS['HOST']}.#{VARS['DOMAIN_NAME']}"

  host_ip = VARS['HOST_PORT_PUBLIC'] ? '0.0.0.0' : '127.0.0.1'
  auto_correct = VARS['HOST_PORT_AUTOCORRECT']
  FORWARDS.each { |fwd|
    config.vm.network :forwarded_port,
                      guest: fwd[:guest],
                      host: fwd[:host],
                      id: fwd[:id],
                      host_ip: host_ip,
                      auto_correct: auto_correct
  }

  config.vm.synced_folder VARS['HOST_SHARE_DIR'], VARS['GUEST_SHARE_DIR']
  config.vm.synced_folder File.join(VARS['HOST_SHARE_DIR'], 'db/hub'), "/var/lib/mysql/#{VARS['HUBNAME']}", owner: 'mysql', group: 'mysql'
  config.vm.synced_folder File.join(VARS['HOST_SHARE_DIR'], 'db/hub_metrics'), "/var/lib/mysql/#{VARS['HUBNAME']}_metrics", owner: 'mysql', group: 'mysql'
  config.vm.synced_folder File.join(VARS['HOST_SHARE_DIR'], 'webroot'), "/var/www/#{VARS['HUBNAME']}", owner: 'vagrant', group: 'apache'
  config.vm.synced_folder File.join(VARS['HOST_SHARE_DIR'], 'webroot/app/cache'), "/var/www/#{VARS['HUBNAME']}/app/cache", owner: 'vagrant', group: 'apache', mount_options: ['dmode=775', 'fmode=664']
  config.vm.synced_folder File.join(VARS['HOST_SHARE_DIR'], 'webroot/app/site/resources'), "/var/www/#{VARS['HUBNAME']}/app/site/resources", owner: 'vagrant', group: 'apache', mount_options: ['dmode=775', 'fmode=664']
  config.vm.synced_folder File.join(VARS['HOST_SHARE_DIR'], '../../api'), "/var/www/#{VARS['HUBNAME']}/app/components/com_prodev/dev/api", owner: 'vagrant', group: 'apache', mount_options: ['dmode=775', 'fmode=664']
  config.vm.synced_folder File.join(VARS['HOST_SHARE_DIR'], '../../spa'), "/var/www/#{VARS['HUBNAME']}/app/components/com_prodev/dev/spa", owner: 'vagrant', group: 'apache', mount_options: ['dmode=775', 'fmode=664']

  config.vm.provider 'virtualbox' do |vb|
    vb.name = "hubzero-#{VARS['HUBNAME']}"
    vb.cpus = VARS['VBOX_CPUS']
    vb.memory = VARS['VBOX_MEMORY']
    vb.gui = !VARS['VBOX_HEADLESS']
    vb.customize ['modifyvm', :id, '--clipboard', 'bidirectional']
  end

  config.vm.provision :shell, path: './provision.sh', privileged: true, env: VARS
end
