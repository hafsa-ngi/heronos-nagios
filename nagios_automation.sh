#!/bin/bash

# -----------------------------------------------
# Configuration and Available Services

base_dir="/usr/local/nagios/etc/servers"

# Nagios service check commands (for NRPE)
declare -A SERVICE_COMMANDS=(
    [1]="check_nrpe!check_disk"
    [2]="check_nrpe!check_http"
    [3]="check_nrpe!check_https"
    [4]="check_nrpe!check_load"
    [5]="check_nrpe!check_mem"
    [6]="check_nrpe!check_ping"
    [7]="check_nrpe!check_ssh"
    [8]="API"
    [9]="Custom"
)

declare -A SERVICE_DESCRIPTIONS=(
    [1]="disk"
    [2]="http"
    [3]="https"
    [4]="load"
    [5]="memory"
    [6]="ping"
    [7]="ssh"
    [8]="api"
    [9]="custom"
)

# Environments - now with sorted keys
environments=("dev" "stage" "prod")

# Rollback system
backup_dir=$(mktemp -d)
created_dirs=()
created_files=()
modified_files=()
rollback_needed=1

# Cleanup and exit function
cleanup_and_exit() {
    if [ $rollback_needed -eq 1 ]; then
        rollback
        echo "Rolling back changes due to error or interruption."
    else
        # Successful run, remove backup_dir
        rm -rf "$backup_dir"
    fi
}

# Rollback function
rollback() {
    echo ""
    echo "Performing rollback..."
    
    # Restore modified files
    for file in "${modified_files[@]}"; do
        if [ -f "$backup_dir/$(basename "$file")" ]; then
            echo "Restoring $file from backup"
            mv "$backup_dir/$(basename "$file")" "$file"
        fi
    done
    
    # Remove created files
    for file in "${created_files[@]}"; do
        if [ -f "$file" ]; then
            echo "Removing created file: $file"
            rm -f "$file"
        fi
    done
    
    # Remove created directories (in reverse order)
    for (( idx=${#created_dirs[@]}-1 ; idx>=0 ; idx-- )); do
        dir="${created_dirs[idx]}"
        if [ -d "$dir" ]; then
            echo "Removing directory: $dir"
            rmdir --ignore-fail-on-non-empty "$dir"
        fi
    done
    
    echo "Rollback complete. Backup files are in $backup_dir"
}

trap cleanup_and_exit EXIT

# Function to get existing services for a host
get_existing_services() {
    local host=$1
    local service_file=$2
    
    if [ ! -f "$service_file" ]; then
        return
    fi
    
    # Extract service descriptions for the specified host
    awk -v host="$host" '
        /define service/ { in_service=1; }
        in_service && /host_name/ && $0 ~ "host_name[[:space:]]+" host { host_match=1; }
        in_service && /service_description/ && host_match { print $2; }
        /}/ { in_service=0; host_match=0; }
    ' "$service_file"
}

# Delete functions
delete_project() {
    echo "Select project to delete:"
    projects=($(ls -1 "$base_dir"))
    for i in "${!projects[@]}"; do
        echo "$((i + 1))) ${projects[$i]}"
    done
    
    read -p "Enter project number: " project_number
    if [[ "$project_number" =~ ^[0-9]+$ ]] && (( project_number >= 1 && project_number <= ${#projects[@]} )); then
        project_name="${projects[$((project_number - 1))]}"
        read -p "Are you sure you want to delete project '$project_name'? (y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            rm -rf "$base_dir/$project_name"
            echo "Project '$project_name' deleted"
        else
            echo "Deletion canceled"
        fi
    else
        echo "Invalid selection"
    fi
}

delete_environment() {
    echo "Select project:"
    projects=($(ls -1 "$base_dir"))
    for i in "${!projects[@]}"; do
        echo "$((i + 1))) ${projects[$i]}"
    done
    
    read -p "Enter project number: " project_number
    if [[ "$project_number" =~ ^[0-9]+$ ]] && (( project_number >= 1 && project_number <= ${#projects[@]} )); then
        project_name="${projects[$((project_number - 1))]}"
        project_dir="$base_dir/$project_name"
        
        echo "Select environment to delete:"
        envs=($(ls -1 "$project_dir"))
        for i in "${!envs[@]}"; do
            echo "$((i + 1))) ${envs[$i]}"
        done
        
        read -p "Enter environment number: " env_number
        if [[ "$env_number" =~ ^[0-9]+$ ]] && (( env_number >= 1 && env_number <= ${#envs[@]} )); then
            env_name="${envs[$((env_number - 1))]}"
            read -p "Are you sure you want to delete environment '$env_name'? (y/n): " confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                rm -rf "$project_dir/$env_name"
                echo "Environment '$env_name' deleted"
            else
                echo "Deletion canceled"
            fi
        else
            echo "Invalid selection"
        fi
    else
        echo "Invalid selection"
    fi
}

delete_host() {
    echo "Select project:"
    projects=($(ls -1 "$base_dir"))
    for i in "${!projects[@]}"; do
        echo "$((i + 1))) ${projects[$i]}"
    done
    
    read -p "Enter project number: " project_number
    if [[ "$project_number" =~ ^[0-9]+$ ]] && (( project_number >= 1 && project_number <= ${#projects[@]} )); then
        project_name="${projects[$((project_number - 1))]}"
        project_dir="$base_dir/$project_name"
        
        echo "Select environment:"
        envs=($(ls -1 "$project_dir"))
        for i in "${!envs[@]}"; do
            echo "$((i + 1))) ${envs[$i]}"
        done
        
        read -p "Enter environment number: " env_number
        if [[ "$env_number" =~ ^[0-9]+$ ]] && (( env_number >= 1 && env_number <= ${#envs[@]} )); then
            env_name="${envs[$((env_number - 1))]}"
            env_dir="$project_dir/$env_name"
            host_cfg="$env_dir/hosts.cfg"
            
            if [ -f "$host_cfg" ]; then
                echo "Select host to delete:"
                hosts=($(grep -E 'host_name\s+' "$host_cfg" | awk '{print $2}'))
                for i in "${!hosts[@]}"; do
                    echo "$((i + 1))) ${hosts[$i]}"
                done
                
                read -p "Enter host number: " host_number
                if [[ "$host_number" =~ ^[0-9]+$ ]] && (( host_number >= 1 && host_number <= ${#hosts[@]} )); then
                    host_name="${hosts[$((host_number - 1))]}"
                    read -p "Are you sure you want to delete host '$host_name'? (y/n): " confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        # Backup before modification
                        if [ ! -f "$backup_dir/hosts.cfg" ]; then
                            cp "$host_cfg" "$backup_dir/hosts.cfg"
                            modified_files+=("$host_cfg")
                        fi
                        
                        # Delete host definition
                        awk -v host="$host_name" '
                            /define host/ { in_host=1; buffer=$0; next }
                            in_host { buffer = buffer ORS $0 }
                            /}/ && in_host { 
                                if ($0 !~ "host_name[[:space:]]+" host) {
                                    print buffer 
                                }
                                in_host=0; buffer=""
                                next
                            }
                            !in_host { print }
                        ' "$host_cfg" > "$host_cfg.tmp" && mv "$host_cfg.tmp" "$host_cfg"
                        
                        # Delete associated services
                        service_cfg="$env_dir/services.cfg"
                        if [ -f "$service_cfg" ]; then
                            # Backup before modification
                            if [ ! -f "$backup_dir/services.cfg" ]; then
                                cp "$service_cfg" "$backup_dir/services.cfg"
                                modified_files+=("$service_cfg")
                            fi
                            
                            awk -v host="$host_name" '
                                /define service/ { in_service=1; buffer=$0; next }
                                in_service { buffer = buffer ORS $0 }
                                /}/ && in_service { 
                                    if ($0 !~ "host_name[[:space:]]+" host) {
                                        print buffer 
                                    }
                                    in_service=0; buffer=""
                                    next
                                }
                                !in_service { print }
                            ' "$service_cfg" > "$service_cfg.tmp" && mv "$service_cfg.tmp" "$service_cfg"
                        fi
                        
                        echo "Host '$host_name' and its services deleted"
                    else
                        echo "Deletion canceled"
                    fi
                else
                    echo "Invalid selection"
                fi
            else
                echo "No hosts found in this environment"
            fi
        else
            echo "Invalid selection"
        fi
    else
        echo "Invalid selection"
    fi
}

delete_service() {
    echo "Select project:"
    projects=($(ls -1 "$base_dir"))
    for i in "${!projects[@]}"; do
        echo "$((i + 1))) ${projects[$i]}"
    done
    
    read -p "Enter project number: " project_number
    if [[ "$project_number" =~ ^[0-9]+$ ]] && (( project_number >= 1 && project_number <= ${#projects[@]} )); then
        project_name="${projects[$((project_number - 1))]}"
        project_dir="$base_dir/$project_name"
        
        echo "Select environment:"
        envs=($(ls -1 "$project_dir"))
        for i in "${!envs[@]}"; do
            echo "$((i + 1))) ${envs[$i]}"
        done
        
        read -p "Enter environment number: " env_number
        if [[ "$env_number" =~ ^[0-9]+$ ]] && (( env_number >= 1 && env_number <= ${#envs[@]} )); then
            env_name="${envs[$((env_number - 1))]}"
            env_dir="$project_dir/$env_name"
            host_cfg="$env_dir/hosts.cfg"
            service_cfg="$env_dir/services.cfg"
            
            if [ -f "$host_cfg" ] && [ -f "$service_cfg" ]; then
                echo "Select host:"
                hosts=($(grep -E 'host_name\s+' "$host_cfg" | awk '{print $2}'))
                for i in "${!hosts[@]}"; do
                    echo "$((i + 1))) ${hosts[$i]}"
                done
                
                read -p "Enter host number: " host_number
                if [[ "$host_number" =~ ^[0-9]+$ ]] && (( host_number >= 1 && host_number <= ${#hosts[@]} )); then
                    host_name="${hosts[$((host_number - 1))]}"
                    
                    echo "Select service to delete:"
                    services=($(get_existing_services "$host_name" "$service_cfg"))
                    for i in "${!services[@]}"; do
                        echo "$((i + 1))) ${services[$i]}"
                    done
                    
                    read -p "Enter service number: " service_number
                    if [[ "$service_number" =~ ^[0-9]+$ ]] && (( service_number >= 1 && service_number <= ${#services[@]} )); then
                        service_name="${services[$((service_number - 1))]}"
                        read -p "Are you sure you want to delete service '$service_name'? (y/n): " confirm
                        if [[ "$confirm" =~ ^[Yy]$ ]]; then
                            # Backup before modification
                            if [ ! -f "$backup_dir/services.cfg" ]; then
                                cp "$service_cfg" "$backup_dir/services.cfg"
                                modified_files+=("$service_cfg")
                            fi
                            
                            # Delete service definition
                            awk -v host="$host_name" -v service="$service_name" '
                                /define service/ { in_service=1; buffer=$0; next }
                                in_service { buffer = buffer ORS $0 }
                                /}/ && in_service { 
                                    if ($0 !~ "host_name[[:space:]]+" host || $0 !~ "service_description[[:space:]]+" service) {
                                        print buffer 
                                    }
                                    in_service=0; buffer=""
                                    next
                                }
                                !in_service { print }
                            ' "$service_cfg" > "$service_cfg.tmp" && mv "$service_cfg.tmp" "$service_cfg"
                            
                            echo "Service '$service_name' deleted"
                        else
                            echo "Deletion canceled"
                        fi
                    else
                        echo "Invalid selection"
                    fi
                else
                    echo "Invalid selection"
                fi
            else
                echo "No services found in this environment"
            fi
        else
            echo "Invalid selection"
        fi
    else
        echo "Invalid selection"
    fi
}

# Main menu
while true; do
    echo ""
    echo "============ Nagios Configuration Manager ============"
    echo "1) Add new monitoring configuration"
    echo "2) Delete project"
    echo "3) Delete environment"
    echo "4) Delete host"
    echo "5) Delete service"
    echo "6) Exit"
    echo "====================================================="
    read -p "Enter your choice: " main_choice
    
    case $main_choice in
        1)
            # Continue with add configuration
            ;;
        2)
            delete_project
            continue
            ;;
        3)
            delete_environment
            continue
            ;;
        4)
            delete_host
            continue
            ;;
        5)
            delete_service
            continue
            ;;
        6)
            rollback_needed=0
            exit 0
            ;;
        *)
            echo "Invalid choice"
            continue
            ;;
    esac
    break
done

# -----------------------------------------------
# Original add configuration flow starts here

# Step 1: List existing projects
echo "Existing projects:"
projects=()
if [ -d "$base_dir" ]; then
    projects=($(ls -1 "$base_dir"))
    for i in "${!projects[@]}"; do
        echo "$((i + 1))) ${projects[$i]}"
    done
    # Add option to create new project
    new_project_index=$(( ${#projects[@]} + 1 ))
    echo "$new_project_index) Create new project"
else
    echo "No projects found. Directory doesn't exist. Creating base dir..."
    mkdir -p "$base_dir"
    echo "1) Create new project"
    new_project_index=1
fi

# Step 2: Ask for project selection
while true; do
    read -p "Enter project number from above list: " project_number
    if [[ "$project_number" =~ ^[0-9]+$ ]] && (( project_number >= 1 && project_number <= new_project_index )); then
        if (( project_number == new_project_index )); then
            read -p "Enter new project name: " project_name
            mkdir -p "$base_dir/$project_name"
            created_dirs+=("$base_dir/$project_name")
            break
        else
            project_name="${projects[$((project_number - 1))]}"
            break
        fi
    else
        echo "Invalid selection. Please enter a valid number."
    fi
done

project_dir="$base_dir/$project_name"

# Step 3: Environment selection - now sorted numerically
echo "Select environment:"
for i in "${!environments[@]}"; do
    echo "$((i + 1))) ${environments[$i]}"
done

while true; do
    read -p "Enter environment number: " env_number
    if [[ "$env_number" =~ ^[0-9]+$ ]] && (( env_number >= 1 && env_number <= ${#environments[@]} )); then
        environment="${environments[$((env_number - 1))]}"
        env_dir="$project_dir/$environment"
        if [ ! -d "$env_dir" ]; then
            mkdir -p "$env_dir"
            created_dirs+=("$env_dir")
        fi
        break
    else
        echo "Invalid selection. Please enter a valid number."
    fi
done

host_cfg="$env_dir/hosts.cfg"
service_cfg="$env_dir/services.cfg"

# Step 4: Host selection - now asks for address
if [ -f "$host_cfg" ]; then
    echo "Existing hosts in $project_name ($environment):"
    hosts=($(grep -E 'host_name\s+' "$host_cfg" | awk '{print $2}'))
    
    # Add option to create new host
    new_host_index=$(( ${#hosts[@]} + 1 ))
    
    for i in "${!hosts[@]}"; do
        echo "$((i + 1))) ${hosts[$i]}"
    done
    echo "$new_host_index) Create new host"
    
    while true; do
        read -p "Enter host number from above list: " host_number
        if [[ "$host_number" =~ ^[0-9]+$ ]] && (( host_number >= 1 && host_number <= new_host_index )); then
            if (( host_number == new_host_index )); then
                read -p "Enter new host name: " host_name
                read -p "Enter host address (IP or FQDN): " host_address
                # Backup if file exists but we're creating new host
                if [ -f "$host_cfg" ] && [ ! -f "$backup_dir/hosts.cfg" ]; then
                    cp "$host_cfg" "$backup_dir/hosts.cfg"
                    modified_files+=("$host_cfg")
                elif [ ! -f "$host_cfg" ]; then
                    created_files+=("$host_cfg")
                fi
                
                echo "define host {" >> "$host_cfg"
                echo "    host_name                       $host_name" >> "$host_cfg"
                echo "    alias                           $host_name" >> "$host_cfg"
                echo "    address                         $host_address" >> "$host_cfg"
                echo "    use                             linux-server" >> "$host_cfg"
                echo "}" >> "$host_cfg"
                break
            else
                host_name="${hosts[$((host_number - 1))]}"
                break
            fi
        else
            echo "Invalid selection. Please enter a valid number."
        fi
    done
else
    echo "No hosts found. Creating new host."
    read -p "Enter new host name: " host_name
    read -p "Enter host address (IP or FQDN): " host_address
    created_files+=("$host_cfg")
    echo "define host {" > "$host_cfg"
    echo "    host_name                       $host_name" >> "$host_cfg"
    echo "    alias                           $host_name" >> "$host_cfg"
    echo "    address                         $host_address" >> "$host_cfg"
    echo "    use                             linux-server" >> "$host_cfg"
    echo "}" >> "$host_cfg"
fi

# Function to add services
add_services() {
    # Get existing services for this host
    existing_services=($(get_existing_services "$host_name" "$service_cfg"))
    
    echo "Available Services:"
    service_keys=($(echo "${!SERVICE_DESCRIPTIONS[@]}" | tr ' ' '\n' | sort -n))
    for key in "${service_keys[@]}"; do
        echo "$key) ${SERVICE_DESCRIPTIONS[$key]}"
    done

    read -p "Enter service numbers to monitor (comma-separated, e.g., 1,2,5): " services_input

    IFS=',' read -r -a selected_services <<< "$services_input"

    # Backup service file if exists and not already backed up
    if [ -f "$service_cfg" ] && [ ! -f "$backup_dir/services.cfg" ]; then
        cp "$service_cfg" "$backup_dir/services.cfg"
        modified_files+=("$service_cfg")
    elif [ ! -f "$service_cfg" ]; then
        created_files+=("$service_cfg")
    fi

    for selected_service in "${selected_services[@]}"; do
        case $selected_service in
            8)  # API Service
                read -p "Enter API endpoint URL: " api_endpoint
                # Clean up endpoint for service description
                clean_endpoint=$(echo "$api_endpoint" | sed 's|https\?://||; s|/|_|g')
                service_description="$host_name-api-$clean_endpoint"
                check_command="check_rest_api!20!$api_endpoint"
                
                echo "Adding API service: $service_description"
                echo "define service {" >> "$service_cfg"
                echo "    host_name                       ngi-monitoring" >> "$service_cfg"
                echo "    service_description             $service_description" >> "$service_cfg"
                echo "    check_command                   $check_command" >> "$service_cfg"
                echo "    use                             api-service,graphed-service" >> "$service_cfg"
                echo "}" >> "$service_cfg"
                ;;
                
            9)  # Custom Service
                read -p "Enter custom service description: " custom_desc
                read -p "Enter custom command (without check_nrpe! prefix): " custom_cmd
                service_description="$host_name-$custom_desc"
                check_command="check_nrpe!$custom_cmd"
                
                echo "Adding custom service: $service_description"
                echo "define service {" >> "$service_cfg"
                echo "    host_name                       $host_name" >> "$service_cfg"
                echo "    service_description             $service_description" >> "$service_cfg"
                echo "    check_command                   $check_command" >> "$service_cfg"
                echo "    use                             generic-service,graphed-service" >> "$service_cfg"
                echo "}" >> "$service_cfg"
                ;;
                
            *)  # Standard Services
                if [[ -n "${SERVICE_COMMANDS[$selected_service]}" ]]; then
                    service_description="${SERVICE_DESCRIPTIONS[$selected_service]}"
                    
                    # Check if service already exists for this host
                    if [[ " ${existing_services[@]} " =~ " $service_description " ]]; then
                        echo "Service '$service_description' already exists for host '$host_name'. Skipping."
                        continue
                    fi
                    
                    check_command="${SERVICE_COMMANDS[$selected_service]}"
                    
                    echo "Adding service: $service_description"
                    echo "define service {" >> "$service_cfg"
                    echo "    host_name                       $host_name" >> "$service_cfg"
                    echo "    service_description             $service_description" >> "$service_cfg"
                    echo "    check_command                   $check_command" >> "$service_cfg"
                    echo "    use                             generic-service,graphed-service" >> "$service_cfg"
                    echo "}" >> "$service_cfg"
                else
                    echo "Invalid service selection: $selected_service"
                fi
                ;;
        esac
    done
}

# Initial service addition
add_services

# Step 6: Prompt for adding more services
while true; do
    read -p "Do you want to add more services for $host_name? (y/n): " add_more_services
    if [[ "$add_more_services" =~ ^[Yy]$ ]]; then
        add_services
    elif [[ "$add_more_services" =~ ^[Nn]$ ]]; then
        break
    else
        echo "Invalid input. Please enter 'y' or 'n'."
    fi
done

echo "Services configuration completed for $host_name."

# Step 7: Validate Nagios configuration
echo ""
echo "Running Nagios configuration validation..."
nagios_output=$(sudo /usr/local/nagios/bin/nagios -v /usr/local/nagios/etc/nagios.cfg 2>&1)

# Show output
echo "$nagios_output"

# Check for "Total Errors:   0"
if echo "$nagios_output" | grep -q "Total Errors:   0"; then
    echo ""
    echo "✅ Nagios configuration check passed: No serious problems were detected."
else
    echo ""
    echo "❌ Nagios configuration check failed: Please review the above output for errors."
fi

# Successful completion - disable rollback
rollback_needed=0
