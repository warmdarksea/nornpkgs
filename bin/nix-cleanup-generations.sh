#!/usr/bin/env bash

# made with claude. i haven't even really read it

set -euo pipefail

# Function to get the booted generation
get_booted_generation() {
    local booted_system_path=$(readlink -f /run/booted-system)
    
    for link in /nix/var/nix/profiles/system-*-link; do
        local gen_num=$(echo "$link" | grep -o '[0-9]\+')
        local gen_path=$(readlink -f "$link")
        
        if [ "$gen_path" = "$booted_system_path" ]; then
            echo "$gen_num"
            return 0
        fi
    done
    
    echo "Could not determine booted generation" >&2
    return 1
}

# Function to get the current generation
get_current_generation() {
    local current_gen=$(sudo nix-env -p /nix/var/nix/profiles/system --list-generations | grep "(current)" | awk '{print $1}')
    
    if [ -z "$current_gen" ]; then
        local current_system_path=$(readlink -f /run/current-system)
        
        for link in /nix/var/nix/profiles/system-*-link; do
            local gen_num=$(echo "$link" | grep -o '[0-9]\+')
            local gen_path=$(readlink -f "$link")
            
            if [ "$gen_path" = "$current_system_path" ]; then
                current_gen="$gen_num"
                break
            fi
        done
    fi
    
    if [ -n "$current_gen" ]; then
        echo "$current_gen"
        return 0
    else
        echo "Could not determine current generation" >&2
        return 1
    fi
}

# Get the booted and current generations
BOOTED_GEN=$(get_booted_generation)
CURRENT_GEN=$(get_current_generation)

if [ -z "$BOOTED_GEN" ] || [ -z "$CURRENT_GEN" ]; then
    echo "Failed to determine required generation numbers."
    exit 1
fi

echo "Booted generation: $BOOTED_GEN"
echo "Current generation: $CURRENT_GEN"

# Convert to integers for comparison
BOOTED_GEN=$(($BOOTED_GEN))
CURRENT_GEN=$(($CURRENT_GEN))

# Handle the case where current might be lower than booted
if [ "$CURRENT_GEN" -lt "$BOOTED_GEN" ]; then
    echo "Current generation ($CURRENT_GEN) is older than booted generation ($BOOTED_GEN)."
    echo "This is unusual but possible. No action will be taken."
    exit 0
fi

# Calculate the range to delete (non-inclusive)
START_DEL=$((BOOTED_GEN + 1))
END_DEL=$((CURRENT_GEN - 1))

if [ "$START_DEL" -gt "$END_DEL" ]; then
    echo "No generations to delete between booted ($BOOTED_GEN) and current ($CURRENT_GEN)."
    exit 0
fi

echo "Will delete generations $START_DEL through $END_DEL (non-inclusive range)."

# Get existing generations to check against the range
EXISTING_GENS=$(sudo nix-env -p /nix/var/nix/profiles/system --list-generations | awk '{print $1}')

# Build the list of generations to delete
GENS_TO_DELETE=""
COUNT_TO_DELETE=0

for i in $(seq $START_DEL $END_DEL); do
    # Check if this generation exists
    if echo "$EXISTING_GENS" | grep -q "^$i$"; then
        GENS_TO_DELETE="$GENS_TO_DELETE $i"
        COUNT_TO_DELETE=$((COUNT_TO_DELETE + 1))
    else
        echo "Note: Generation $i does not exist, skipping."
    fi
done

if [ "$COUNT_TO_DELETE" -eq 0 ]; then
    echo "No generations to delete in the specified range."
    exit 0
fi

echo "Will delete these generations:$GENS_TO_DELETE"
echo "Total generations to delete: $COUNT_TO_DELETE"

# Confirm with user
read -p "Proceed with deletion? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 1
fi

# Delete all generations at once
echo "Removing generations:$GENS_TO_DELETE..."
sudo nix-env --profile /nix/var/nix/profiles/system --delete-generations $GENS_TO_DELETE

# Garbage collection step removed as requested

echo "Done! Remaining generations:"
sudo nix-env -p /nix/var/nix/profiles/system --list-generations
