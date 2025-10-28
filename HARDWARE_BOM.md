<!--
    HARDWARE_BOM.md

    This file documents the complete hardware Bill of Materials (BOM) for the Rackmate T0 Parrot MCP Edge Node project. It provides a detailed list of required and optional components, system overview, power and cooling diagrams, networking layout, assembly checklist, and sourcing references. The BOM is intended to guide users through the assembly and sourcing of parts for building a compact 4U AI edge computing chassis based on the Raspberry Pi 5 platform.
-->
# 🧰 Rackmate T0 Hardware Bill of Materials (BOM)

This document lists all components, parts, and optional accessories required to build a **Rackmate T0 Parrot MCP Edge Node** — a compact 4U chassis designed for AI edge computing and network orchestration with a Raspberry Pi 5 core.

---

## ⚙️ System Overview

| Subsystem                | Function                  | Space |
|-------------------------|---------------------------|-------|
| Front 2U LCD module     | Display / user interface  | 2 U   |
| Raspberry Pi 5 (8 GB)   | Compute + control node    | 1 U   |
| Patch panel             | Network I/O interface     | 1 U   |
| Cooling + power         | Thermal management, power | Shared|

Total: 4U open-frame chassis.

---

## 🧩 Core Components

| Part                        | Model / Spec                | Qty | Notes / Link                                      |
|-----------------------------|-----------------------------|-----|---------------------------------------------------|
| Rackmate T0 mini rack (4 U) | Aluminum/steel hybrid frame | 1   | With carry handles                                |
| 19" wide 2U HDMI LCD        | 1920 × 360 recommended      | 1   | Touch optional; HDMI + USB power; e.g. Waveshare  |
| Raspberry Pi 5 (8 GB RAM)   | Main processing node        | 1   | [Official Reseller](https://www.raspberrypi.com/) |
| 80 mm 12 V PWM fan          | Connect to Pi GPIO PWM      | 1   | Pin 18 via transistor                             |
| 5 V 5 A USB-C PD adapter    | Pi + display combined draw  | 1   | ~20–25 W                                          |
| 12-port Cat6 1U mini panel  | RJ45 Keystone               | 1   | Rear punch-down or pass-through                   |
| 8-port Gigabit unmanaged    | e.g. TP-Link TL-SG108       | 1   | Mount behind patch panel                          |
| Dual-band 802.11ac USB 3.0  | For wireless AP/mesh        | 1   |                                                   |
| ≥ 64 GB UHS-I A2 class      | System + logs + MCP data    | 1   | microSD card                                      |
| Micro HDMI → HDMI           | Connect Pi → LCD            | 1   |                                                   |
| Cat6 short patch leads      | Panel interconnects         | 12  |                                                   |
| M3 bolts, washers, spacers  | For securing components     | –   |                                                   |
| 12 V fan harness, Velcro    | Cable management            | –   |                                                   |

---

## ⚡ Power Distribution Diagram

[AC 100–240 V]
↓
[5 V USB-C PD adapter]───→ Raspberry Pi 5 (power)
│
├──→ Display (USB 5 V)
└──→ Fan rail (12 V boost converter optional)

---

## 🌬 Cooling & Thermal Notes

- Target: < 60 °C under sustained load
- Recommended: PWM fan via GPIO control or Noctua low-noise 5 V fan
- Add adhesive heat sinks on Pi 5 SoC, PMIC, RAM

---

## 🔌 Networking Layout

[External WAN]──→[Switch]──→[Patch Panel Ports 1-12]──→[Devices/Agents]
│
└──→[Raspberry Pi 5 (MCP Server)]

---

## 🧠 Optional Enhancements

| Add-on                        | Function                        | Example Source                |
|-------------------------------|----------------------------------|-------------------------------|
| 0.96" I²C OLED                | Display CPU temp / network stats |                               |
| PiJuice HAT                   | Short power backup               |                               |
| DS18B20                       | Environmental telemetry          |                               |
| Powered USB 3.0 hub           | Extra power & connectivity       |                               |
| Custom STL files (TBD)        | Internal wire management         |                               |

---

## 🧪 Assembly Checklist

1. Mount Rackmate T0 frame.
2. Install LCD (2 U) → connect HDMI + USB.
3. Mount 12-port patch panel rear.
4. Fix Raspberry Pi 5 (1 U tray) + active cooling.
5. Connect Ethernet and HDMI runs.
6. Route power wiring cleanly through rear vent.
7. Boot Parrot MCP Server and verify network visibility.

---

## 🔗 Sourcing References

*(example links — replace with verified vendor URLs)*

- [AliExpress Rackmate T0](https://www.aliexpress.com/)
- [Waveshare 19" Bar LCD](https://www.waveshare.com/)
- [Official Raspberry Pi 5](https://www.raspberrypi.com/products/raspberry-pi-5/)
- [Amazon Cat6 1U Mini Panel](https://www.amazon.com/)
- [Noctua 80 mm + 12 V DC Adapter](https://noctua.at/)
