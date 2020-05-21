# -*- mode: ruby -*-
# vi: set ft=ruby :

# Load user variables
require 'yaml'

def find_file(fn, dir='.')
  while true
    path = File.join dir, fn
    break if File.file? path or File.file?(File.join dir, 'Vagrantfile')
    dir = File.expand_path File.join dir, '..'
  end
  return path
end

VARS = YAML.load(File.read(find_file('vars.yml')))
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
  config.vm.synced_folder File.join(VARS['HOST_SHARE_DIR'], 'webroot'), "/var/www/#{VARS['HUBNAME']}", owner: 'apache', group: 'apache'

  config.vm.provider 'virtualbox' do |vb|
    vb.name = "hubzero-#{VARS['HUBNAME']}"
    vb.cpus = VARS['VBOX_CPUS']
    vb.memory = VARS['VBOX_MEMORY']
    vb.gui = !VARS['VBOX_HEADLESS']
    vb.customize ['modifyvm', :id, '--clipboard', 'bidirectional']
  end

  config.vm.provision :shell, path: './provision.sh', privileged: true, env: VARS
end
