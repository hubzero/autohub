usermod -a -G apache vagrant
yum -y install colordiff jq ncdu php56-php-pecl-xdebug tmux tree vim
git config --global color.ui auto
mv -f ~/.gitconfig /etc/gitconfig
echo export GREP_OPTIONS='--color=auto' >> /etc/bashrc
echo 'set -g mouse-mode on' > /home/vagrant/.tmux.conf
