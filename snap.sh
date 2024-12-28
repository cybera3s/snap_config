#!/usr/bin/env bash

# Author: Ario
# Date Created: 2024/05/04
# Date Modified: 2024/12/28
# Description
# First setup for bare vps
# usage
# snap.sh

# check if user is root
if [[ $EUID -ne 0 ]]; then
	echo "Please Run it as 'root' user"
	exit 0
fi

clear -x
echo "********************************************************** Snap Config **********************************************************"

# Get Data
read -rp "Enter your admin username: " admin_user
echo ""
read -rp "Enter your admin password: " admin_user_pw
echo ""
read -rp "Enter your desired ssh port: " my_ssh_port
echo ""

now=$(date +%F)
script_name=$(basename "$0")
required_packages=(zsh python3-pip at members supervisor gh curl git psmisc cmake)
out_logs_file="$script_name"_"$now".out.logs
err_log_file="$script_name"_"$now".err.logs
admin_home=/home/$admin_user

# sshd vars
sshd_config_file=/etc/ssh/sshd_config
sshd_backup_path=/root/sshd_config_original
client_alive_interval=10
client_alive_max=1

# git vars
git_username=cybera3s
git_email=cybera.3s@gmail.com

# zsh vars
zsh_config_file="$admin_home"/.zshrc
zsh_custom_folder="$admin_home"/.oh-my-zsh/custom/plugins
zshrc_link=https://raw.githubusercontent.com/cybera3s/vps_config/master/src/.zshrc
oh_my_zsh_install_link=https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh
zsh_autosuggestions_link="https://github.com/zsh-users/zsh-autosuggestions.git"
zsh_autosuggestions_path="$zsh_custom_folder"/zsh-autosuggestions
zsh_syntax_highlighting_link="https://github.com/zsh-users/zsh-syntax-highlighting.git"
zsh_syntax_highlighting_path="$zsh_custom_folder"/zsh-syntax-highlighting

# poetry
poetry_home=/opt/poetry

log_command() {
	# Takes a command and logs its standard output and standard error to provided files
	# Parameters:
	# First paramater is the command to evaluate
	# Second parameter is the optional path to standard output log file
	# Third parameter is the optional path to standard output log file
	local command="$1"
	local out_log="${2:-$out_logs_file}"
	local err_log="${3:-$err_log_file}"

	eval "$command" >>"$out_log" 2>>"$err_log"
}

run_as_admin() {
	# Takes a command and runs it as provided admin user
	# if user not provided default is admin_user var

	local command="$1"
	local admin="${2:-$admin_user}"

	sudo -u "$admin" bash -c "$command"
}

update_system() {
	# update and upgrade

	echo "Update and upgradeing system"

	# NO input just default settings
	export DEBIAN_FRONTEND=noninteractive

	if apt update && DEBIAN_FRONTEND=noninteractive apt upgrade -y; then
		echo -e "System was updated and upgraded successfully!\n"
	fi

	return 0
}

install_requirements() {
	# Installs provided required packages and remove extra ones

	local packages=("$@")

	echo "Installing requirements"
	IFS=,
	echo "Required packages are: ${packages[*]}"

	for pack in "${packages[@]}"; do

		if log_command "apt install $pack -y"; then
			echo "'$pack' Installed successfully!"
		else
			echo "'$pack' Failed to install!"
		fi
	done

	if log_command "apt autoremove -y"; then
		echo "Removing unnecessary packages was successful!"
	fi

	echo -e "Requirements installed and extra dependencies was removed!\n"

	return 0
}

add_sudo_user() {
	# Adds a super user with zsh shell and sudo group with provided username and password

	local shell
	shell="$(which zsh)"
	local hashed_password
	local password=$2
	hashed_password=$(openssl passwd -1 "$password")
	local group=sudo
	local username=$1

	# if user exists
	if id "$username"; then
		echo "user $username already Exists!"
		return 0
	fi

	log_command "useradd -m -s '$shell' -G '$group' -p '$hashed_password' $username"

	local exit_code=$?

	if [ "$exit_code" -eq 0 ]; then
		echo "Super User with username '$username' added successfully!"
	else
		echo "Error: Failed to add the user '$username'."
	fi

	return 0

}

backup_sshd() {
	# Creates a backup of sshd config file

	local sshd_path=$1
	local backup_path=$2

	log_command "cp $sshd_path $backup_path"
	echo -e "Done! sshd backup file saved at '$backup_path'\n"
}

change_sshd_port() {
	# Changes current ssh port number with provided port number

	local current_port
	local provided_port=$1
	local sshd_config_path=$2
	current_port=$(grep -oP "(?<=^Port )...." "$sshd_config_path")

	log_command "sed -i 's/#\?Port .*/Port $provided_port/g' $sshd_config_path"

	echo -e "Done!ssh port number changed from $current_port > $provided_port\n"
	return 0
}

change_root_login_status() {
	# Changes root login status in sshd_config file
	# Parameters:
	# $1 > status : should be 'yes' or 'no'
	# $2 > sshd_config_path

	local status=$1
	local sshd_config_path=$2
	local current_root_login_status
	current_root_login_status=$(grep -Eo "^PermitRootLogin (yes|no)" "$sshd_config_path" | awk '{print $2}')

	# Check if the status is either "yes" or "no"
	if [[ "$status" != "yes" && "$status" != "no" ]]; then
		echo "Invalid status. It should be 'yes' or 'no'."
		status=no
	fi

	log_command "sed -i 's/PermitRootLogin $current_root_login_status/PermitRootLogin $status/g' $sshd_config_path"
	echo -e "Done!root login status changed from $current_root_login_status > $status\n"

	return 0

}

change_sshd_client_alive() {
	# Changes the ClientAliveCountMax and ClientAliveInterval variables
	# with provided data
	# Parameters:
	# $1 > int a number represent ClientAliveCountMax
	# $2 > int a number represent ClientAliveInterval
	# $3 > path to sshd config file

	local sshd_config_path=$3
	local current_count
	current_count=$(grep "#\?ClientAliveCountMax.*" "$sshd_config_path" | awk '{print $2}')
	local current_interval
	current_interval=$(grep "#\?ClientAliveInterval.*" "$sshd_config_path" | awk '{print $2}')
	local count=$1
	local interval=$2

	log_command "sed -i 's/#\?ClientAliveCountMax $current_count/ClientAliveCountMax $count/' $sshd_config_path"
	log_command "sed -i 's/#\?ClientAliveInterval $current_interval/ClientAliveInterval $interval/' $sshd_config_path"

	echo -e "Done!ClientAliveCountMax changed from $current_count > $count"
	echo -e "Done!ClientAliveInterval changed from $current_interval > $interval\n"
	return 0
}

set_git_config() {
	# Set GIT system wide configuration
	# Parameters:
	# $1 > str to represent git username
	# $2 > str to represent git email address

	local git_username=$1
	local git_email=$2

	log_command "git config --system user.name $git_username"
	log_command "git config --system user.email $git_email"

	echo -e "GIT configurations is set\n"
	return 0
}

install_ohmyzsh() {
	# Installs oh my zsh for provided admin user
	# with the oh my zsh install path

	local install_path=$1

	run_as_admin "sh -c $(curl -fsSL "$install_path")"
	echo -e "Installed oh my zsh successfully!\n"
	return 0
}

generate_zshrc_config() {
	# Adds prepared .zshrc file

	cat <<'EOT' >>$zsh_config_file
# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time oh-my-zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="candy"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git python zsh-autosuggestions zsh-syntax-highlighting)

source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='mvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch x86_64"

# Set personal aliases, overriding those provided by oh-my-zsh libs,
# plugins, and themes. Aliases can be placed here, though oh-my-zsh
# users are encouraged to define aliases within the ZSH_CUSTOM folder.
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

# My aliases
alias cls=clear
export TZ='Asia/Tehran'
alias python=python3
alias cls=clear

# set poetry path
export PATH="/home/ario/.local/bin:$PATH"
EOT

	return 0
}

add_zsh_plugin() {
	# Adds provided oh my zsh custom plugin

	local plugin_link=$1
	local path=$2

	run_as_admin "git clone $plugin_link $path"

	echo -e "ZSH plugin cloned from '$plugin_link' to $path\n"
	return 0
}
install_poetry() {
	# Installs poetry system wide on provided path
	local path=$1

	echo -e "Installing Poetry!\n"
	log_command "curl -sSL https://install.python-poetry.org | POETRY_HOME=$path python3 -"

	echo -e "Poetry installed at '$path'\n"
	return 0
}
configure_poetry() {
	# Adds poetry to provided shell config path and sets virtualenvs.in-project true

	local path=$1

	echo "***************** Configuring Poetry *****************"

	log_command "echo 'export PATH=\$PATH:/opt/poetry/bin/' >>$path"
	echo "poetry exported at: $path"

	su - "$admin_user" -c "/opt/poetry/bin/poetry config virtualenvs.in-project true"
	cmd=$(su - "$admin_user" -c "/opt/poetry/bin/poetry config virtualenvs.in-project")
	echo -e "poetry config virtualenvs.in-project: $cmd\n"

	return 0
}

config_sshd() {
	backup_sshd "$sshd_config_file" "$sshd_backup_path"

	change_sshd_port "$my_ssh_port" "$sshd_config_file"

	change_root_login_status "no" "$sshd_config_file"

	change_sshd_client_alive "$client_alive_max" "$client_alive_interval" "$sshd_config_file"

}

# Main
main() {
	clear -x

	update_system

	install_requirements "${required_packages[@]}"

	# Create a new admin user
	add_sudo_user "$admin_user" "$admin_user_pw"

	# Config SSH daemon
	config_sshd

	# restart ssh daemon
	systemctl restart sshd

	set_git_config "$git_username" "$git_email"

	install_ohmyzsh "$oh_my_zsh_install_link"

	generate_zshrc_config

	add_zsh_plugin "$zsh_autosuggestions_link" "$zsh_autosuggestions_path"
	add_zsh_plugin "$zsh_syntax_highlighting_link" "$zsh_syntax_highlighting_path"

	# chenage owner and group to admin user
	chown -R "$admin_user:$admin_user" "$admin_home"

	install_poetry "$poetry_home"

	configure_poetry "$zsh_config_file"
	configure_poetry "/root/.bashrc"

	# chenage owner and group to admin user
	chown -R "$admin_user:$admin_user" "$admin_home"

}

main | tee "$out_logs_file"
