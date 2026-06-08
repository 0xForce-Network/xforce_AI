# xforce_AI Nushell environment

let xforce_venv_dir = if (($env.VENV_DIR? | default "") == "") { "/venv/main" } else { $env.VENV_DIR }
let xforce_venv_bin = ($xforce_venv_dir | path join "bin")
let xforce_current_path = ($env.PATH? | default [])

if not ($xforce_current_path | any {|path_entry| $path_entry == $xforce_venv_bin }) {
  $env.PATH = ($xforce_current_path | prepend $xforce_venv_bin)
}

if (($env.WORKSPACE_DIR? | default "") == "") {
  $env.WORKSPACE_DIR = "/workspace"
}

if (($env.VENV_DIR? | default "") == "") {
  $env.VENV_DIR = $xforce_venv_dir
}
