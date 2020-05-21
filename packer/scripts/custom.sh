yum -y install colordiff jq ncdu tmux vim
git config --global color.ui auto
mv -f ~/.gitconfig /etc/gitconfig
echo export GREP_OPTIONS='--color=auto' >> /etc/bashrc
