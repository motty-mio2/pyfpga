#
# PyFPGA Master Tcl
#
# Copyright (C) 2015-2020 INTI
# Copyright (C) 2015-2020 Rodrigo A. Melo
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# Description: Tcl script to create a new project and performs synthesis,
# implementation and bitstream generation.
#
# Supported TOOLs: ise, libero, quartus, vivado
#
# Notes:
# * fpga_ is used to avoid name collisions.
# * The 'in' operator was introduced by Tcl 8.5, but some Tools uses 8.4,
#   so 'lsearch' is used to test if a value is in a list.
#

#
# Things to tuneup (#SOMETHING#) for each project
#

set TOOL     #TOOL#
set PRESYNTH #PRESYNTH#
set PROJECT  #PROJECT#
set PART     #PART#
set FAMILY   #FAMILY#
set DEVICE   #DEVICE#
set PACKAGE  #PACKAGE#
set SPEED    #SPEED#
set TOP      #TOP#
# TASKS = prj syn imp bit
set TASKS    [list #TASKS#]

set PARAMS   [list #PARAMS#]

proc fpga_files {} {
#FILES#
}

proc fpga_commands { PHASE } {
    fpga_print "setting commands for the phase '$PHASE'"
    switch $PHASE {
        "prefile" {
#PREFILE_CMDS#
        }
        "project" {
#PROJECT_CMDS#
        }
        "preflow" {
#PREFLOW_CMDS#
        }
        "postsyn" {
#POSTSYN_CMDS#
        }
        "postimp" {
#POSTIMP_CMDS#
        }
        "postbit" {
#POSTBIT_CMDS#
        }
    }
}

#
# Procedures
#

proc fpga_print { MSG } {
    global TOOL
    puts ">>> PyFPGA ($TOOL): $MSG"
}

proc fpga_create { PROJECT } {
    global TOOL
    fpga_print "creating the project '$PROJECT'"
    switch $TOOL {
        "ise"     {
            if { [ file exists $PROJECT.xise ] } { file delete $PROJECT.xise }
            project new $PROJECT.xise
        }
        "libero"  {
            if { [ file exists $PROJECT ] } { file delete -force -- $PROJECT }
            new_project -name $PROJECT -location $PROJECT -hdl {VHDL} -family {SmartFusion2}
        }
        "quartus" {
            package require ::quartus::project
            project_new $PROJECT -overwrite
            set_global_assignment -name NUM_PARALLEL_PROCESSORS ALL
        }
        "vivado"  { create_project -force $PROJECT }
    }
}

proc fpga_open { PROJECT } {
    global TOOL
    fpga_print "opening the project '$PROJECT'"
    switch $TOOL {
        "ise"     { project open $PROJECT.xise }
        "libero"  {
            open_project $PROJECT/$PROJECT.prjx
        }
        "quartus" {
            package require ::quartus::flow
            project_open -force $PROJECT.qpf
        }
        "vivado"  { open_project $PROJECT }
    }
}

proc fpga_close {} {
    global TOOL
    fpga_print "closing the project"
    switch $TOOL {
        "ise"     { project close }
        "libero"  { close_project }
        "quartus" { project_close }
        "vivado"  { close_project }
    }
}

proc fpga_part { PART } {
    global TOOL FAMILY DEVICE PACKAGE SPEED
    fpga_print "adding the part '$PART'"
    switch $TOOL {
        "ise"     {
            project set family  $FAMILY
            project set device  $DEVICE
            project set package $PACKAGE
            project set speed   $SPEED
        }
        "libero"  {
            set_device -family $FAMILY -die $DEVICE -package $PACKAGE -speed $SPEED
        }
        "quartus" {
            set_global_assignment -name DEVICE $PART
        }
        "vivado"  {
            set_property "part" $PART [current_project]
        }
    }
}

proc fpga_file {FILE {LIBRARY "work"}} {
    global TOOL TOP
    set message "adding the file '$FILE'"
    if { $LIBRARY != "work" } { append message " (into the VHDL library '$LIBRARY')" }
    fpga_print $message
    regexp -nocase {\.(\w*)$} $FILE -> ext
    if { $ext == "tcl" } {
        source $FILE
        return
    }
    switch $TOOL {
        "ise" {
            if {$ext == "xcf"} {
                project set "Synthesis Constraints File" $FILE -process "Synthesize - XST"
            } elseif { $LIBRARY != "work" } {
                lib_vhdl new $LIBRARY
                xfile add $FILE -lib_vhdl $LIBRARY
            } else {
                xfile add $FILE
            }
        }
        "libero" {
            global LIBERO_PLACE_CONSTRAINTS
            global LIBERO_OTHER_CONSTRAINTS
            if {$ext == "pdc"} {
                create_links -io_pdc $FILE
                append LIBERO_PLACE_CONSTRAINTS "-file $FILE "
            } elseif {$ext == "sdc"} {
                create_links -sdc $FILE
                append LIBERO_PLACE_CONSTRAINTS "-file $FILE "
                append LIBERO_OTHER_CONSTRAINTS "-file $FILE "
            } else {
                create_links -library $LIBRARY -hdl_source $FILE
                build_design_hierarchy
            }
        }
        "quartus" {
            if {$ext == "v"} {
                set TYPE VERILOG_FILE
            } elseif {$ext == "sv"} {
                set TYPE SYSTEMVERILOG_FILE
            } elseif {$ext == "vhdl" || $ext == "vhd"} {
                set TYPE VHDL_FILE
            } elseif {$ext == "sdc"} {
                set TYPE SDC_FILE
            } else {
                set TYPE SOURCE_FILE
            }
            if { $LIBRARY != "work" } {
                set_global_assignment -name $TYPE $FILE -library $LIBRARY
            } else {
                set_global_assignment -name $TYPE $FILE
            }
        }
        "vivado" {
            if { $LIBRARY != "work" } {
                add_files $FILE
                set_property library $LIBRARY [get_files $FILE]
            } else {
                add_files $FILE
            }
        }
    }
}

proc fpga_include {PATH} {
    global TOOL INCLUDED
    lappend INCLUDED $PATH
    fpga_print "setting '$PATH' as a search location"
    switch $TOOL {
        "ise" {
            # Verilog Included Files are NOT added
            project set "Verilog Include Directories" \
            [join $INCLUDED "|"] -process "Synthesize - XST"
        }
        "libero" {
            # Verilog Included Files are ALSO added
            # They must be specified after set_root (see fpga_top)
            foreach FILE [glob -nocomplain $PATH/*.vh] {
                create_links -hdl_source $FILE
            }
            build_design_hierarchy
        }
        "quartus" {
            # Verilog Included Files are NOT added
            foreach INCLUDE $INCLUDED {
                set_global_assignment -name SEARCH_PATH $INCLUDE
            }
        }
        "vivado" {
            # Verilog Included Files are NOT added
            set_property "include_dirs" $INCLUDED [current_fileset]
        }
    }
}

proc fpga_design {FILE} {
    global TOOL TOP INCLUDED
    fpga_print "including the block design '$FILE'"
    switch $TOOL {
        "vivado" {
            if { [info exists INCLUDED] && [llength $INCLUDED] > 0 } {
                set_property "ip_repo_paths" $INCLUDED [get_filesets sources_1]
                update_ip_catalog -rebuild
            }
            source $FILE
            make_wrapper -force -files [get_files design_1.bd] -top -import
            if { $TOP == "UNDEFINED"} {
                set TOP design_1_wrapper
            }
        }
        default  { puts "UNSUPPORTED by '$TOOL'" }
    }
}

proc fpga_top { TOP } {
    global TOOL
    fpga_print "specifying the top level '$TOP'"
    switch $TOOL {
        "ise"     {
            project set top $TOP
        }
        "libero"  {
            set_root $TOP
            # Verilog Included files
            global INCLUDED PARAMS
            set cmd "configure_tool -name {SYNTHESIZE} -params {SYNPLIFY_OPTIONS:"
            if { [info exists INCLUDED] && [llength $INCLUDED] > 0 } {
                # See <ROOT>/poc/include/libero.tcl for details
                set PATHS "../../"
                append PATHS [join $INCLUDED ";../../"]
                append cmd "set_option -include_path \"$PATHS\""
                append cmd "\n"
            }
            foreach PARAM $PARAMS {
                set assign [join $PARAM]
                append cmd "set_option -hdl_param -set \"$assign\""
                append cmd "\n"
            }
            append cmd "}"
            eval $cmd
            # Constraints
            # PDC is only used for PLACEROUTE.
            # SDC is used by ALL (SYNTHESIZE, PLACEROUTE and VERIFYTIMING).
            global LIBERO_PLACE_CONSTRAINTS
            global LIBERO_OTHER_CONSTRAINTS
            if { [info exists LIBERO_OTHER_CONSTRAINTS] } {
                set cmd "organize_tool_files -tool {SYNTHESIZE} "
                append cmd $LIBERO_OTHER_CONSTRAINTS
                append cmd "-module $TOP -input_type {constraint}"
                eval $cmd
                set cmd "organize_tool_files -tool {VERIFYTIMING} "
                append cmd $LIBERO_OTHER_CONSTRAINTS
                append cmd "-module $TOP -input_type {constraint}"
                eval $cmd
            }
            if { [info exists LIBERO_PLACE_CONSTRAINTS] } {
                set cmd "organize_tool_files -tool {PLACEROUTE} "
                append cmd $LIBERO_PLACE_CONSTRAINTS
                append cmd "-module $TOP -input_type {constraint}"
                eval $cmd
            }
        }
        "quartus" {
            set_global_assignment -name TOP_LEVEL_ENTITY $TOP
        }
        "vivado"  {
            set_property top $TOP [current_fileset]
        }
    }
}

proc fpga_params {} {
    global TOOL PARAMS
    if { [llength $PARAMS] == 0 } { return }
    fpga_print "setting generics/parameters"
    switch $TOOL {
        "ise"     {
            set assigns [list]
            foreach PARAM $PARAMS { lappend assigns [join $PARAM "="] }
            project set "Generics, Parameters" "[join $assigns]" -process "Synthesize - XST"
        }
        "libero"  {
            # They must be specified after set_root (see fpga_top)
        }
        "quartus" {
            foreach PARAM $PARAMS {
                eval "set_parameter -name $PARAM"
            }
        }
        "vivado"  {
            set assigns [list]
            foreach PARAM $PARAMS { lappend assigns [join $PARAM "="] }
            set obj [get_filesets sources_1]
            set_property "generic" "[join $assigns]" -objects $obj
        }
    }
}

proc fpga_run_syn {} {
    global TOOL PRESYNTH
    fpga_print "running 'synthesis'"
    switch $TOOL {
        "ise"     {
            if { $PRESYNTH == "True" } {
                project set top_level_module_type "EDIF"
            } else {
                project clean
                process run "Synthesize"
                if { [process get "Synthesize" status] == "errors" } { exit 2 }
            }
        }
        "libero"  {
            run_tool -name {SYNTHESIZE}
        }
        "quartus" {
            execute_module -tool map
        }
        "vivado"  {
            if { $PRESYNTH == "True" } {
                set_property design_mode GateLvl [current_fileset]
            } else {
                reset_run synth_1
                launch_runs synth_1
                wait_on_run synth_1
            }
        }
        default  { puts "UNSUPPORTED by '$TOOL'" }
    }
}

proc fpga_run_imp {} {
    global TOOL PRESYNTH
    fpga_print "running 'implementation'"
    switch $TOOL {
        "ise"     {
            process run "Translate"
            if { [process get "Translate" status] == "errors" } { exit 2 }
            process run "Map"
            if { [process get "Map" status] == "errors" } { exit 2 }
            process run "Place & Route"
            if { [process get "Place & Route" status] == "errors" } { exit 2 }
        }
        "libero"  {
            run_tool -name {PLACEROUTE}
            run_tool -name {VERIFYTIMING}
        }
        "quartus" {
            execute_module -tool fit
            execute_module -tool sta
        }
        "vivado"  {
            if {$PRESYNTH == "False"} {
                open_run synth_1
            }
            launch_runs impl_1
            wait_on_run impl_1
        }
        default  { puts "UNSUPPORTED by '$TOOL'" }
    }
}

proc fpga_run_bit {} {
    global TOOL PROJECT TOP
    fpga_print "running 'bitstream generation'"
    switch $TOOL {
        "ise"     {
            process run "Generate Programming File"
            if { [process get "Generate Programming File" status] == "errors" } { exit 2 }
            catch { file rename -force $TOP.bit $PROJECT.bit }
        }
        "libero"  {
            run_tool -name {GENERATEPROGRAMMINGFILE}
        }
        "quartus" {
            execute_module -tool asm
        }
        "vivado"  {
            open_run impl_1
            write_bitstream -force $PROJECT
        }
        default  { puts "UNSUPPORTED by '$TOOL'" }
    }
}

#
# Start of the script
#

fpga_print "start of the Tcl script (interpreter $tcl_version)"

#
# Project Creation
#

if { [lsearch -exact $TASKS "prj"] >= 0 } {
    fpga_print "running the Project Creation"
    if { [catch {
        fpga_create $PROJECT
        fpga_part $PART
        fpga_commands "prefile"
        fpga_files
        fpga_top $TOP
        fpga_params
        fpga_commands "project"
        fpga_close
    } ERRMSG]} {
        puts "ERROR: there was a problem creating a New Project.\n"
        puts $ERRMSG
        exit 1
    }
}

#
# Design Flow
#

if { [lsearch -regexp $TASKS "syn|imp|bit"] >= 0 } {
    fpga_print "running the Design Flow"
    if { [catch {
        fpga_open $PROJECT
        fpga_commands "preflow"
        if { [lsearch -exact $TASKS "syn"] >= 0 } {
            fpga_run_syn
            fpga_commands "postsyn"
        }
        if { [lsearch -exact $TASKS "imp"] >= 0 } {
            fpga_run_imp
            fpga_commands "postimp"
        }
        if { [lsearch -exact $TASKS "bit"] >= 0 } {
            fpga_run_bit
            fpga_commands "postbit"
        }
        fpga_close
    } ERRMSG]} {
        puts "ERROR: there was a problem running the Design Flow.\n"
        puts $ERRMSG
        exit 2
    }
}

#
# End of the script
#

fpga_print "end of the Tcl script"
