#!/usr/bin/env bash

# Author: Ario
# Date Created: 2024/05/04
# Date Modified: 2024/12/28
# Description
# First setup for bare VPS
# usage
# snap.sh

# Color definitions
GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m" # No Color

# Show script banner
show_banner() {
	clear -x
	echo -e "${BLUE}**********************************************************"
	echo -e "${CYAN}  VPS First-Time Setup Script"
	echo -e "${CYAN}  Author      : Ario"
	echo -e "${CYAN}  Version     : 1.2"
	echo -e "${CYAN}  Date        : $(date +%F)"
	echo -e "${CYAN}  Description : Automates initial VPS configuration"
	echo -e "${BLUE}**********************************************************${NC}"

	# Summary of what the script will do
	echo -e "${YELLOW}This script will:${NC}"
	echo -e "${GREEN}  ✔ Update and upgrade your system"
	echo -e "${GREEN}  ✔ Add a new admin user with ZSH and Oh-My-Zsh"
	echo -e "${GREEN}  ✔ Configure and harden SSH (port, root access)"
	echo -e "${GREEN}  ✔ Install Docker and configure it without sudo"
	echo -e "${GREEN}  ✔ Install Poetry and basic Python tools"
	echo -e "${GREEN}  ✔ Configure Git"
	echo -e "${GREEN}  ✔ Enable and configure UFW firewall"
	echo -e "${GREEN}  ✔ Set up ZSH plugins and aliases${NC}"
	echo ""
}

# check if user is root
if [[ $EUID -ne 0 ]]; then
	echo -e "${RED}Please Run it as 'root' user${NC}"
	exit 0
fi

clear -x
echo -e "${BLUE}********************************************************** Snap Config **********************************************************${NC}"

# Validate input
validate_input() {
	if [[ -z "$1" ]]; then
		echo -e "${RED}Input cannot be empty. Exiting.${NC}"
		exit 1
	fi
}

# Get Data
read -rp "Enter your admin username: " admin_user
validate_input "$admin_user"
echo ""

read -rsp "Enter your admin password: " admin_user_pw
validate_input "$admin_user_pw"
echo ""

read -rp "Enter your desired ssh port (default: 9011): " my_ssh_port
my_ssh_port="${my_ssh_port:-9011}"
if ! [[ "$my_ssh_port" =~ ^[0-9]+$ ]] || ((my_ssh_port < 1024 || my_ssh_port > 65535)); then
	echo -e "${RED}Invalid port number. Must be between 1024–65535.${NC}"
	exit 1
fi
echo ""

now=$(date +%F)
script_name=$(basename "$0")
required_packages=(zsh python3-pip at members supervisor gh curl git psmisc cmake ufw bc)
out_logs_file="$script_name"_"$now".out.logs
err_log_file="$script_name"_"$now".err.logs
admin_home=/home/$admin_user

# sshd vars
sshd_config_file=/etc/ssh/sshd_config
sshd_backup_path=/root/sshd_config_original
client_alive_interval=0
client_alive_max=3

# git vars
git_username=cybera3s
git_email=cybera.3s@gmail.com

# zsh vars
zsh_config_file="$admin_home"/.zshrc
zsh_custom_folder="$admin_home"/.oh-my-zsh/custom/plugins
# zshrc_link=https://raw.githubusercontent.com/cybera3s/vps_config/master/src/.zshrc
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
	local user="${1:-admin_user}"
	shift

	if [[ -z "$user" || $# -eq 0 ]]; then
		echo "❌ Error: user and command must be specified!" >&2
		return 1
	fi

	if ! id "$user" &>/dev/null; then
		echo "❌ Error: user '$user' does not exist." >&2
		return 1
	fi

	if ! command -v sudo &>/dev/null; then
		echo "❌ Error: 'sudo' is not installed or not in PATH." >&2
		return 1
	fi

	# Combine the args into a command string and run it as the target user in a new bash shell
	sudo -u "$user" bash -c "$*"
}

update_system() {
	# update and upgrade

	echo -e "${BLUE}Updating system...${NC}"

	echo -e "${BLUE}Checking internet connection...${NC}\n"
	if ! ping -c 1 8.8.8.8 &>/dev/null; then
		echo -e "${RED}Internet connection not available. Exiting...${NC}"
		exit 1
	fi
	# NO input just default settings
	export DEBIAN_FRONTEND=noninteractive

	apt update && apt upgrade -y && echo -e "${GREEN}System updated successfully!${NC}\n"
	return 0
}

install_requirements() {
	# Installs provided required packages and remove extra ones
	echo -e "${BLUE}Installing requirements...${NC}"
	local packages=("$@")

	IFS=,
	echo -e "${BLUE}Required packages are: ${packages[*]}${NC}"

	for pack in "${packages[@]}"; do

		if log_command "apt install $pack -y"; then
			echo -e "${GREEN}✔ '$pack' Installed successfully!${NC}"
		else
			echo -e "${RED}✖ '$pack' Failed to install!${NC}"
		fi
	done

	if log_command "apt autoremove -y"; then
		echo -e "${GREEN}Removed unnecessary packages.${NC}"
	fi
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
	if id "$username" &>/dev/null; then
		echo -e "${YELLOW}User '$username' already exists.${NC}"
		return 0
	fi

	log_command "useradd -m -s '$shell' -G '$group' -p '$hashed_password' $username"

	local exit_code=$?

	if [ "$exit_code" -eq 0 ]; then
		echo -e "${GREEN}✔ User '$username' created successfully.${NC}\n"
	else
		echo -e "${RED}✖ Failed to add the user '$username'.${NC}\n"
		exit 1
	fi

	return 0

}

backup_sshd() {
	# Creates a backup of sshd config file

	local sshd_path=$1
	local backup_path=$2

	log_command "cp $sshd_path $backup_path"
	echo -e "${GREEN}✔ SSHD config backed up to '$backup_path'${NC}\n"
}

change_sshd_port() {
	# Changes current ssh port number with provided port number

	local provided_port=$1
	local sshd_config_path=$2

	log_command "sed -i 's/#\?Port .*/Port $provided_port/g' $sshd_config_path"

	echo -e "${GREEN}✔ Done! ssh port number changed to '$provided_port'${NC}\n"
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
	echo -e "${GREEN}✔ Done!root login status changed from '$current_root_login_status' to '$status'${NC}\n"

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

	echo -e "${GREEN}Done!ClientAliveCountMax changed from '$current_count' to '$count'${NC}"
	echo -e "${GREEN}Done!ClientAliveInterval changed from '$current_interval' to '$interval'${NC}\n"
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

	echo -e "${GREEN}✔ GIT configurations is set${NC}\n"
	return 0
}

install_ohmyzsh() {
	local url="${1:-https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh}"

	if [ -d "$HOME/.oh-my-zsh" ]; then
		echo -e "${YELLOW}⚠ Oh My Zsh is already installed at $HOME/.oh-my-zsh. Skipping installation.${NC}"
		return 0
	fi

	if ! command -v zsh >/dev/null 2>&1; then
		echo -e "${YELLOW}⚠ Zsh is not installed. Please install it first.${NC}"
		return 1
	fi

	sh -c "$(curl -fsSL "$url")"
	echo -e "${GREEN}✔ Oh My Zsh installed.${NC}"
}

generate_zshrc_config() {
	local zsh_config_file="$HOME/.zshrc"

	if [[ ! -e "$zsh_config_file" ]]; then
		echo -e "${RED}'${zsh_config_file}' does not exists so create it${NC}"
		touch "${zsh_config_file}"
	fi

	cat <<'EOT' >>"$zsh_config_file"
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
	local plugin_link="$1"
	local path="$2"

	# Check required arguments
	if [[ -z "$plugin_link" || -z "$path" ]]; then
		echo "❌ Missing plugin link or path." >&2
		return 1
	fi

	# Check if git is installed
	if ! command -v git &>/dev/null; then
		echo "❌ git is not installed. Cannot clone plugin." >&2
		return 2
	fi

	# Check if plugin directory already exists
	if [[ -d "$path" ]]; then
		echo "ℹ️ Plugin already exists at: $path"
		return 0
	fi

	# Attempt to clone
	if git clone "$plugin_link" "$path"; then
		echo -e "${GREEN:-}✔ ZSH plugin cloned from '$plugin_link' to '$path'${NC:-}\n"
	else
		echo "❌ Failed to clone plugin from $plugin_link" >&2
		return 3
	fi
}

add_zsh_plugins() {
	add_zsh_plugin "https://github.com/zsh-users/zsh-autosuggestions.git" "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
	add_zsh_plugin "https://github.com/zsh-users/zsh-syntax-highlighting.git" "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
}


install_poetry() {
	# Installs poetry system wide on provided path
	local path=$1

	echo -e "${GREEN}***************** Installing Poetry *****************${NC}"
	log_command "curl -sSL https://install.python-poetry.org | POETRY_HOME=$path python3 -"
	echo -e "${GREEN}Poetry installed at '$path'${NC}\n"
	return 0
}

configure_poetry() {
	# Adds poetry to provided shell config path and sets virtualenvs.in-project true

	local path=$1

	echo -e "${BLUE}***************** configuring Poetry *****************${NC}"

	log_command "echo 'export PATH=\$PATH:/opt/poetry/bin/' >>$path"
	echo -e "${GREEN}poetry exported at the zsh config file in: '$path'${NC}"

	su - "$admin_user" -c "/opt/poetry/bin/poetry config virtualenvs.in-project true"
	cmd=$(su - "$admin_user" -c "/opt/poetry/bin/poetry config virtualenvs.in-project")
	echo -e "${GREEN}poetry config virtualenvs.in-project: $cmd${NC}\n"

	return 0
}

config_sshd() {
	backup_sshd "$sshd_config_file" "$sshd_backup_path"

	change_sshd_port "$my_ssh_port" "$sshd_config_file"

	change_root_login_status "no" "$sshd_config_file"

	change_sshd_client_alive "$client_alive_max" "$client_alive_interval" "$sshd_config_file"

}

configure_ufw() {
	echo -e "${BLUE}****************************${NC} Configuring UFW (Firewall) ${BLUE}****************************${NC}"

	# Allow custom SSH port
	ufw allow "$my_ssh_port"/tcp

	# Default policies
	ufw default deny incoming
	ufw default allow outgoing

	# Enable firewall
	ufw --force enable

	echo -e "${GREEN}UFW firewall enabled and configured successfully.${NC}"
}

install_docker() {
	echo -e "${BLUE}*************************** Installing Docker... *************************** ${NC}"
	apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
	echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg]     https://download.docker.com/linux/ubuntu     $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
	apt update
	apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

	echo -e "${GREEN}Docker installed.${NC}"
	usermod -aG docker "$admin_user"
	usermod -aG docker root
	echo -e "${GREEN}Docker access granted to '$admin_user' and root without sudo.${NC}"
}

show_system_info() {
	echo -e "${BLUE}==================== System Information ====================${NC}"

	echo -e "${CYAN}Hostname     :${NC} $(hostname)"
	echo -e "${CYAN}OS           :${NC} $(lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')"
	echo -e "${CYAN}Kernel       :${NC} $(uname -r)"
	echo -e "${CYAN}Architecture :${NC} $(uname -m)"

	echo -e "${CYAN}CPU          :${NC} $(lscpu | grep 'Model name' | awk -F: '{print $2}' | xargs)"
	echo -e "${CYAN}Cores        :${NC} $(nproc)"

	echo -e "${CYAN}Memory Total :${NC} $(free -h | awk '/^Mem:/ {print $2}')"
	echo -e "${CYAN}Disk Total   :${NC} $(lsblk -d -o SIZE | grep -v SIZE | paste -sd+ - | bc) GB"

	echo -e "${CYAN}Uptime       :${NC} $(uptime -p)"

	echo -e "${BLUE}============================================================${NC}"
	echo ""
}

# Main
main() {
	clear -x
	show_banner
	show_system_info
	update_system

	configure_ufw
	install_requirements "${required_packages[@]}"

	# Create a new admin user
	add_sudo_user "$admin_user" "$admin_user_pw"

	# Config SSH daemon
	config_sshd

	# restart ssh daemon
	systemctl restart sshd

	set_git_config "$git_username" "$git_email"

	run_as_admin "install_ohmyzsh '$oh_my_zsh_install_link'"

	run_as_admin "generate_zshrc_config"

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
