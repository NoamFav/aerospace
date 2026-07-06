<div align="center">

<img src="https://capsule-render.vercel.app/api?type=venom&height=220&color=gradient&customColorList=12&text=AEROSPACE&fontSize=80&fontColor=fff&animation=twinkling&desc=Tiling+WM+Configs%2C+Project-Aware&descSize=18&descAlignY=65&stroke=FFFFFF&strokeWidth=1" alt="aerospace Banner" />

<img src="https://readme-typing-svg.herokuapp.com?font=Fira+Code&size=20&pause=1000&color=00D9FF&center=true&vCenter=true&multiline=true&repeat=true&width=900&height=60&lines=One+workspace+per+project+%C2%B7+auto+monitor%2Flaptop+swap;Configs+for+github.com%2Fnikitabobko%2FAeroSpace" alt="Typing SVG" />

<br>

[![Shell](https://img.shields.io/badge/Shell-89E051?style=for-the-badge&logo=gnubash&logoColor=black&labelColor=0D1117)](https://www.gnu.org/software/bash/)
[![AeroSpace](https://img.shields.io/badge/AeroSpace-000000?style=for-the-badge&logo=apple&logoColor=white&labelColor=0D1117)](https://github.com/nikitabobko/AeroSpace)

</div>

<img src="https://user-images.githubusercontent.com/73097560/115834477-dbab4500-a447-11eb-908a-139a6edaec5c.gif" width="100%">

<div align="center">
  <img src="https://readme-typing-svg.herokuapp.com?font=Orbitron&size=26&pause=1000&color=00D9FF&center=true&width=800&lines=%F0%9F%A4%96+WHAT+IS+THIS+%3F" alt="What is this" />
</div>
<br>

Configs and scripts for [AeroSpace](https://github.com/nikitabobko/AeroSpace), a tiling window manager for macOS. Two things this adds on top of stock AeroSpace:

- **Monitor/laptop auto-swap** — `switch.sh` detects a 4K external display and swaps in the right `aerospace.toml` (and toggles Sketchybar's minimal mode) automatically.
- **Per-project workspace launcher** — `projects/*.sh` scripts each open the right editor/terminal layout for a given repo (Nvim-config, Zvezda, coast, iris, etc.) in one command.

<img src="https://user-images.githubusercontent.com/73097560/115834477-dbab4500-a447-11eb-908a-139a6edaec5c.gif" width="100%">

<div align="center">
  <img src="https://readme-typing-svg.herokuapp.com?font=Orbitron&size=26&pause=1000&color=6A5ACD&center=true&width=800&lines=%E2%9C%A8+USAGE+%E2%9C%A8" alt="Usage" />
</div>
<br>

```sh
git clone https://github.com/NoamFav/aerospace ~/.config/aerospace

./switch.sh              # pick monitor vs laptop config based on connected display
./run.sh                 # start/apply aerospace with current config
./projects/coast.sh       # jump straight into a project's workspace layout
```

<details>
<summary><b>📁 Files</b></summary>
<br>

| File | Purpose |
|------|---------|
| `aerospace.toml` | Active config (swapped in by `switch.sh`) |
| `aerospace-monitor.toml` / `aerospace-laptop.toml` | Display-specific configs |
| `lib.sh` | Shared shell helpers |
| `projects/*.sh` | One launcher script per project workspace |

</details>

<img src="https://user-images.githubusercontent.com/73097560/115834477-dbab4500-a447-11eb-908a-139a6edaec5c.gif" width="100%">

<div align="center">

<img src="https://readme-typing-svg.herokuapp.com?font=Orbitron&size=20&pause=1000&color=6A5ACD&center=true&width=800&lines=Thanks+for+stopping+by!" alt="Footer typing" />

<br>

Made with ♥ by [NoamFav](https://github.com/NoamFav)

<img src="https://capsule-render.vercel.app/api?type=waving&height=100&color=gradient&customColorList=12&section=footer" />

</div>
