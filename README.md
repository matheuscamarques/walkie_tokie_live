# Project Setup

## Requirements

* Elixir >= latest
* Erlang >= latest
* [Sox](http://sox.sourceforge.net/) (for audio manipulation)
* [ZeroTier](https://www.zerotier.com/) (to join the private network)
* AppSignal (optional monitoring service)

---

## Connecting to the VPN (ZeroTier)

1. Install ZeroTier on your machine:

   ```bash
   curl -s https://install.zerotier.com | sudo bash
   ```

2. Join your designated network:

   ```bash
   sudo zerotier-cli join <YOUR_NETWORK_ID>
   ```

3. Approve your device in the ZeroTier Web UI:

   Visit [https://my.zerotier.com](https://my.zerotier.com), find your device, and authorize it.

4. Confirm the network interface is available:

   ```bash
   ip a    # or ifconfig
   ```

---

## Installing Sox

Sox is required for audio operations.

### Ubuntu/Debian:

```bash
sudo apt install sox libsox-fmt-all
```

### macOS (Homebrew):

```bash
brew install sox
```

---

## Configuring AppSignal

1. Add the dependency to your `mix.exs`:

   ```elixir
   defp deps do
     [
       {:appsignal, "~> 2.0"}
     ]
   end
   ```

2. Configure AppSignal in `config/appsignal.exs`:

   ```elixir
   use Mix.Config

   config :appsignal, :config,
     name: "your_project_name",
     push_api_key: "your_api_key",
     env: Mix.env()
   ```

3. Set the environment variable in your shell or `.env` file:

   ```bash
   export APPSIGNAL_PUSH_API_KEY=your_api_key
   ```

---

## Running the Project

Make sure your node is connected to the VPN and that the IP address used matches the one shown in your ZeroTier interface.

To run the Phoenix server:

```bash
PORT=4000 iex --name server@10.241.169.206 --cookie 1234 -S mix phx.server
```

Explanation:

* `--name` defines the distributed Erlang node name.
* `--cookie` ensures only nodes with the same cookie can communicate.
* Replace `10.241.169.206` with your actual ZeroTier IP.

---

## About `:master_nodes` Configuration

In a distributed Elixir system, the application may need to connect to one or more master nodes to form a cluster. This is configured using the `:master_nodes` option in your config files.

```elixir
config :walkie_tokie, :master_nodes, [
  :"server@10.241.169.206"
  # :"server@10.0.0.84"
]
```

* Each entry should be a node in the format `"name@ip_address"`.
* The list can include multiple nodes for redundancy or load distribution.
* This configuration allows the node to automatically attempt to connect to the listed master nodes on startup.

### Important Notes

* All nodes must use the same `--cookie` value.
* All nodes must be connected to the same ZeroTier VPN and be reachable via their ZeroTier-assigned IPs.
* The node name used in `--name` must exactly match the name defined in `:master_nodes`.

