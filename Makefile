# Caminho do comando mix
MIX_CMD=iex --sname

# Porta base
BASE_PORT=4000
SERVER_NAME=server

# Start do servidor principal
start-server:
	@echo "Iniciando server na porta $(BASE_PORT)..."
	@PORT=$(BASE_PORT) $(MIX_CMD) $(SERVER_NAME) -S mix phx.server &

# Start dos peers de 1 a 11
start-peers:
	@for i in $$(seq 1 11); do \
		PORT=$$((4000 + $$i)); \
		NAME="peer$$i"; \
		echo "Iniciando $$NAME na porta $$PORT..."; \
		PORT=$$PORT $(MIX_CMD) $$NAME -S mix phx.server & \
	done

# Start de tudo (server + peers)
start-all: start-server start-peers
	@echo "Todos os serviços foram iniciados."

# Kill de todos os peers e do server
stop-all:
	@echo "Parando todas as instâncias usando iex --remsh..."
	@# Parando o servidor principal
	@echo "Parando o servidor na porta $(BASE_PORT)..."
	@if pgrep -f "iex --sname $(SERVER_NAME) -S mix phx.server" > /dev/null; then \
		echo "Conectando ao servidor (node: $(SERVER_NAME)) e enviando comando de parada..."; \
		iex --remsh $(SERVER_NAME)@web-engenharia -e "System.stop()"; \
		echo "Comando de parada enviado para o servidor. Aguarde o encerramento."; \
	else \
		echo "Nenhum processo de servidor encontrado."; \
	fi

	@# Parando os peers
	@for i in $$(seq 1 11); do \
		NAME="peer$$i"; \
		if pgrep -f "iex --sname $$NAME -S mix phx.server" > /dev/null; then \
			echo "Conectando ao peer $$i (node: $$NAME) e enviando comando de parada..."; \
			iex --remsh $$NAME@`web-engenharia` -e "System.stop()"; \
			echo "Comando de parada enviado para o peer $$i. Aguarde o encerramento."; \
		else \
			echo "Nenhum processo de peer $$i encontrado."; \
		fi; \
	done
	@echo "Processo de parada de todas as instâncias concluído."


# Restart de tudo
restart-all: stop-all start-all
	@echo "Reinicialização completa."
