#!/usr/bin/env bash
# One-time setup for the warehouse world (worlds/default_warehouse.sdf).
# Installs the two models it needs (depot, person) from Gazebo Fuel and copies the world
# where the sim launcher looks for it. Safe to re-run.
# The Fuel "Depot" model has no collisions (walls, shelves and crates are visual only, so the
# drone flies through them); this adds mesh collisions so crashes are real.
# Usage: bash sim/warehouse_setup.sh   then   GZ_WORLD=default_warehouse bash sim/demo.sh
set -e
REPO=$(cd "$(dirname "$0")/.." && pwd)
STORE=~/.simulation-gazebo
FUEL=~/.gz/fuel/fuel.gazebosim.org/openrobotics/models

echo "[warehouse] downloading models from Gazebo Fuel"
gz fuel download -u "https://fuel.gazebosim.org/1.0/OpenRobotics/models/Depot"
gz fuel download -u "https://fuel.gazebosim.org/1.0/OpenRobotics/models/Standing person"

# Copy the newest downloaded version into the model store under the names the world uses
install_model() {  # <fuel name> <model:// name>
  local src; src=$(ls -d "$FUEL/$1"/*/ | sort -V | tail -1)
  rm -rf "$STORE/models/$2"; cp -r "$src" "$STORE/models/$2"
}
install_model depot depot
install_model "standing person" person

echo "[warehouse] adding collisions to depot, making person mesh path local"
python3 - "$STORE/models" <<'EOF'
import sys, re
m = sys.argv[1]
# depot: one mesh collision per solid part, inserted into the main link
p = m + '/depot/model.sdf'; s = open(p).read()
if '<collision name="WALLS"' not in s:
    parts = ['WALLS', 'BOXSET', 'PILLERS', 'STAIRS', 'FireAlarmPole']
    col = ''.join(f'''
            <collision name="{n}">
                <geometry><mesh><scale>0.6 0.6 0.6</scale><uri>meshes/Depot.dae</uri>
                    <submesh><name>{n}</name><center>false</center></submesh></mesh></geometry>
            </collision>''' for n in parts)
    col += '''
            <collision name="crates">
                <geometry><mesh><scale>0.6 0.6 0.6</scale><uri>meshes/Crates.dae</uri></mesh></geometry>
            </collision>'''
    s = s.replace('<visual name="ROOF_visual">', col.lstrip() + '\n            <visual name="ROOF_visual">', 1)
    # static: otherwise the physics engine checks the whole building mesh every step (RTF drops to ~0.4)
    s = s.replace('<static>false</static>', '<static>true</static>', 1)
    open(p, 'w').write(s)
# person: mesh URIs point at the Fuel server; use the local copy so it works offline.
# Static scenery: a falling mesh person inside the building mesh also slows the sim down.
p = m + '/person/model.sdf'; s = open(p).read()
s = re.sub(r'https://fuel\.gazebosim\.org/[^<]*/files/meshes/', 'meshes/', s)
if '<static>' not in s:
    s = re.sub(r'(<model name="[^"]*">)', r'\1\n    <static>true</static>', s, count=1)
open(p, 'w').write(s)
EOF

mkdir -p "$STORE/worlds"
cp "$REPO/worlds/default_warehouse.sdf" "$STORE/worlds/"
echo "[warehouse] done. Run: GZ_WORLD=default_warehouse bash sim/demo.sh"
