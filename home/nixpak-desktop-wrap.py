#!/usr/bin/env python3
import os
import sys
import shlex
import argparse

def process_desktop_file(in_path, orig_exe, wrapped_exe):
    # Read the desktop file content
    with open(in_path, 'r') as f:
        lines = f.readlines()
    
    # Process each line
    result_lines = []
    
    for line in lines:
        line = line.rstrip('\n')
        
        # Skip empty lines or comments
        if not line.strip() or line.strip()[0] == '#':
            result_lines.append(line)
            continue
        
        # Process Exec lines
        if line.strip().startswith('Exec='):
            key, value = line.strip().split('=', 1)
            
            # Parse the exec line properly (handles quotes, spaces, etc)
            try:
                parts = shlex.split(value)
            except ValueError:
                # If parsing fails, just keep the original line commented
                result_lines.append(f"# {line} # failed to parse")
                continue
            
            if not parts:
                result_lines.append(line)
                continue
            
            # Get the executable (first part)
            executable = parts[0]
            
            # Check if it matches orig_exe (either exact match or ends with /orig_exe)
            if executable == orig_exe or executable.endswith('/' + orig_exe):
                # Replace with wrapped_exe and keep the rest of the arguments
                new_parts = [wrapped_exe] + parts[1:]
                # Join back, re-quoting if necessary
                new_value = ' '.join(shlex.quote(p) if ' ' in p or any(c in p for c in ['%', '$', '"', "'"]) else p for p in new_parts)
                result_lines.append(f"{key}={new_value}")
            else:
                # Comment out the line and add explanation
                result_lines.append(f"# {line} # couldn't match {orig_exe}")
        else:
            result_lines.append(line)
    
    # Join the lines and return
    return '\n'.join(result_lines)

def main():
    parser = argparse.ArgumentParser(description='Process .desktop file to replace executable.')
    parser.add_argument('in_path', help='Path to the input .desktop file')
    parser.add_argument('orig_exe', help='Name of the executable to replace')
    parser.add_argument('wrapped_exe', help='Full path to the executable to replace with')
    
    args = parser.parse_args()
    
    if not os.path.exists(args.in_path):
        print(f"Error: File {args.in_path} does not exist", file=sys.stderr)
        sys.exit(1)
    
    result = process_desktop_file(args.in_path, args.orig_exe, args.wrapped_exe)
    print(result)

if __name__ == '__main__':
    main()
