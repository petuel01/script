#!/bin/bash

# Configuration
USER_DIR_BASE="/home/users"
LOG_FILE="/var/log/user_directory_management.log"

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run as root."
  exit 1
fi

# Ensure the base directory exists
if [ ! -d "$USER_DIR_BASE" ]; then
    echo "Creating base directory: $USER_DIR_BASE"
    mkdir -p "$USER_DIR_BASE" || { echo "Error: Failed to create base directory $USER_DIR_BASE"; exit 1; }
fi

# Validate username format
validate_username() {
    local username=$1
    if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        echo "Error: Invalid username format."
        exit 1
    fi
}

# Validate size limit
validate_size_limit() {
    local size_limit=$1
    if ! [[ "$size_limit" =~ ^[0-9]+$ ]]; then
        echo "Error: Size limit must be a number in KB."
        exit 1
    fi
}

# Function to create a Linux user if it doesn't exist
create_linux_user() {
    local username=$1
    local password=$2

    if id "$username" &>/dev/null; then
        echo "User $username already exists."
    else
        echo "Creating user $username..."
        useradd -m -d "$USER_DIR_BASE/$username" -s /bin/bash "$username" || { echo "Error: Failed to create user $username"; exit 1; }
        echo "$username:$password" | chpasswd || { echo "Error: Failed to set password for $username"; exit 1; }
        echo "User $username created and password set."
    fi
}

# Function to create a user directory (already done via -m -d above, so ensure ownership only)
# Function to create a user directory (already done via -m -d above, so ensure ownership only)
create_user_directory() {
    local username=$1
    local user_dir="$USER_DIR_BASE/$username"

    if [ ! -d "$user_dir" ]; then
        echo "Creating directory for user $username: $user_dir"
        mkdir -p "$user_dir" || { echo "Error: Failed to create directory $user_dir"; exit 1; }
    fi

    # Set permissions so Nginx or other services can access it
    chown root:root "$user_dir" || { echo "Error: Failed to change ownership to root"; exit 1; }
    chmod 755 "$user_dir" || { echo "Error: Failed to set permissions to 755"; exit 1; }

    echo "Permissions for $user_dir set to root:root with 755 access."
}


# Function to monitor and enforce size limits
monitor_and_enforce_limits() {
    local username=$1
    local size_limit=$2
    local user_dir="$USER_DIR_BASE/$username"

    if [ ! -d "$user_dir" ]; then
        echo "Error: Directory for user $username does not exist: $user_dir"
        exit 1
    fi

    dir_size=$(du -sk "$user_dir" | cut -f1)

    if [ "$dir_size" -gt "$size_limit" ]; then
        msg="Directory $user_dir exceeds the size limit of $size_limit KB (Current size: $dir_size KB)"
        echo "Warning: $msg"
        echo "$(date): $msg" >> "$LOG_FILE"
        logger -t user_dir_mgmt "$msg"
    else
        echo "Directory $user_dir is within the size limit of $size_limit KB (Current size: $dir_size KB)"
    fi
}

# Main logic
main() {
    local username password size_limit

    if [[ $# -eq 3 ]]; then
        username=$1
        password=$2
        size_limit=$3
    else
        read -p "Enter the username: " username
        read -s -p "Enter the password: " password
        echo ""
        read -p "Enter the size limit in KB (e.g., 2000000 for 2GB): " size_limit
    fi

    validate_username "$username"
    validate_size_limit "$size_limit"

    create_linux_user "$username" "$password"
    create_user_directory "$username"
    monitor_and_enforce_limits "$username" "$size_limit"

    # Print summary
    local user_dir="$USER_DIR_BASE/$username"
    local dir_size=$(du -sh "$user_dir" | cut -f1)
    echo ""
    echo "========================================="
    echo "User Directory Setup Summary"
    echo "========================================="
    echo "Username:          $username"
    echo "Home Directory:    $user_dir"
    echo "Size Limit:        $size_limit KB"
    echo "Current Directory Size: $dir_size"
    echo "========================================="
    echo "Setup completed successfully."
}

main "$@"
