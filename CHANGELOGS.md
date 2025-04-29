# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),  
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

## [0.0.2] - 2025-04-29

### Fixed
- Fixed a bug where the `WalkieTokieWeb.WalkieTokieLive` module was not properly updating the UI when an `node` was added or removed.

### Changed
- `WalkieTokie.ConnectSenders` now uses `:net_kernel.monitor_nodes(true)` to monitor nodes instead of an routine.
  - This change improves the performance and reliability of node monitoring.
  - `WalkieTokie.ConnectSenders` now broadcasts a message though **Phonix.PubSub** when a node is added or removed which is used to update the UI.

## [0.0.1] - 2025-04-27

### Added
- `@docmodules` were added to each module for documentation purposes.
- An `inactive` state was introduced in `WalkieTokieWeb.WalkieTokieLive` to track users who are connected to the node but not actively using the app.
- The UI now tracks the state of users connected to the node:
  - `online`: user is connected and using the app.
  - `inactive`: user is connected but not interacting with the app.
  - `offline`: user is disconnected from the node.

### Fixed
- `SenderDynamicSupervisor` now starts the sender process only if the target node is not `nil`.
- `WalkieTokie.MasterConnector` now includes two new functions to abstract the connection logic to master nodes:
  - `get_master_nodes/0`: retrieves the list of master nodes.
  - `schedule_reconnect/0`: schedules a reconnect attempt to master nodes after 10 seconds.
- Fixed chat message container styling to correctly adjust to dark mode.

### Changed
- Master nodes are now defined as a list in the `config.exs` file.
- The Finite State Machine logic was moved to a separate module to be reused in the upcoming `WalkieTokie.TransferFSM`.
- UI text for voice activity was updated to be more user-friendly and intuitive.