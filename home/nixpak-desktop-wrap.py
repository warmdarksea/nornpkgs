#!/usr/bin/env python3
import os
import sys
import re
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
            
            # Check if the executable matches orig_exe
            # We need to handle different patterns like:
            # - Exec=orig_exe
            # - Exec=orig_exe %F
            # - Exec=/path/to/orig_exe
            # - Exec="/path/to/orig_exe"
            
            # Extract the executable part
            if re.search(r'(^|/)' + re.escape(orig_exe) + r'(\s|$)', value):
                # Replace the executable
                new_value = re.sub(r'(^|/)' + re.escape(orig_exe) + r'(\s|$)', 
                                  r'\1' + wrapped_exe + r'\2', value, 1)
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
    parser.add_argument('wrapped_exe', help='Name of the executable to replace with')
    
    args = parser.parse_args()
    
    if not os.path.exists(args.in_path):
        print(f"Error: File {args.in_path} does not exist", file=sys.stderr)
        sys.exit(1)
    
    result = process_desktop_file(args.in_path, args.orig_exe, args.wrapped_exe)
    print(result)

if __name__ == '__main__':
    main()
