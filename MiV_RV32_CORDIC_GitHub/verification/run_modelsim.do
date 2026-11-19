# MODEL SIM / LIBERO project required. Run from the Transcript with:
# do "C:/your-git-repo/verification/run_modelsim.do"
# 1. Set the actual RTL directory in the line below.
# 2. The vendor Mi-V RTL is not bundled in this GitHub repository.
set hdl_dir "C:/Libero v2024.09/icicle-kit-reference-design-2024.09/MPFS_ICICLE/hdl"
set work_root [file normalize [file join [file dirname [info script]] ".."]]

if {![file exists [file join $hdl_dir miv_rv32_pkg.v]]} {
    error "Missing miv_rv32_pkg.v; update hdl_dir in verification/run_modelsim.do"
}
if {[catch {quit -sim}]} { }
vlog -sv -work presynth [file join $hdl_dir miv_rv32_pkg.v]
vlog -sv -work presynth [file join $hdl_dir miv_rv32_hart_merged.v]
vlog -sv -work presynth [file join $work_root verification tb_miv_cpu_ln_exp_standalone.sv]
vsim -L presynth -L PolarFire presynth.tb_miv_cpu_ln_exp_standalone
add wave -r /tb_miv_cpu_ln_exp_standalone/*
run 100 us
wave zoom full
