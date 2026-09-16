# PathPulse AGENTS.md

## Project Overview

PathPulse is a senior design project for assistive haptic navigation and obstacle awareness.

The system consists of:

- iOS application written in Swift
- Two BLE haptic wristbands using ESP32-C3 microcontrollers
- Ray-Ban Meta smart glasses for live camera input
- VL53L5CX depth sensor connected to an ESP32-C3
- Apple Vision / Core ML object detection running on the iPhone

The iPhone is the central processing and control device.

## Repository Structure

- `ios-app/` - Swift/Xcode iOS application
- `firmware/wristband/` - ESP32-C3 wristband firmware
- `firmware/depth-module/` - ESP32-C3 depth sensor firmware
- `hardware/` - schematics, PCB files, and hardware documentation
- `docs/` - project documentation

## Development Scope

This repository contains development for the complete PathPulse system, including:

- iOS application
- Wristband firmware
- Depth-sensing firmware
- Hardware design and PCB files
- System integration and testing

Work may occur across multiple subsystems in parallel.

When making changes, only modify the subsystem relevant to the requested task unless changes to another subsystem are necessary for integration.

## iOS Development

- Language: Swift
- IDE: Xcode
- Target: iPhone
- Prefer native Apple frameworks where practical.
- BLE communication should use CoreBluetooth.
- Vision processing will later use Apple Vision and Core ML.
- Keep navigation, BLE, vision, and UI logic separated into clear components.

## Architecture

The iPhone acts as the system hub.

Navigation path:

Google Maps / routing service
-> iOS application
-> navigation decision logic
-> BLE
-> left/right wristband

Obstacle path:

Ray-Ban Meta camera
-> iOS app
-> Vision/Core ML

VL53L5CX
-> ESP32-C3
-> BLE
-> iOS app

Camera + depth data
-> obstacle decision logic
-> wristband warning

Obstacle warnings should eventually have priority over normal navigation cues.

## Development Guidelines

- Make small, focused changes.
- Do not rewrite unrelated files.
- Explain architectural changes before making large refactors.
- Prefer readable code over clever code.
- Avoid unnecessary dependencies.
- Keep hardware-specific assumptions configurable where possible.
- Do not commit API keys, secrets, certificates, or credentials.
- Add comments where hardware protocols or non-obvious logic require explanation.
- Preserve compatibility with Xcode and standard Swift tooling.

## Function Documentation

All new or modified functions, methods, and initializers must have a JSDoc-style
`/** ... */` comment immediately above their declaration, including protocol
methods and local helper functions.

- Explain what the function does.
- Add `@param` for each parameter, using its internal parameter name.
- Add `@return` to describe the returned value; omit it for initializers and functions returning `Void`.
- Add `@throws` for throwing functions.
- Document relevant units and non-obvious side effects.
- Keep comments accurate when changing the implementation.
- Use this convention in Swift as well as firmware code.

## Git

- Do not force push.
- Do not rewrite history unless explicitly requested.
- Keep commits focused on one logical change.
- Use descriptive commit messages.

## Safety Scope

PathPulse is an assistive obstacle-awareness prototype.

Do not describe the system as:
- autonomous navigation
- obstacle avoidance
- a replacement for a mobility aid
- a safety-critical navigation system

The system provides navigation cues and obstacle warnings only.