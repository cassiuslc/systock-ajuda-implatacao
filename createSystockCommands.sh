#!/bin/bash

# Variáveis para o script systock
SYSTOCK_FILE="/usr/local/bin/systock"

# Verifica se o script está sendo executado com privilégios de superusuário
if [ "$(id -u)" -ne 0 ]; then
    echo "Este script deve ser executado com privilégios de superusuário (sudo)."
    exit 1
fi

# Verifica se o arquivo já existe e remove
if [ -f "$SYSTOCK_FILE" ]; then
    echo "Removendo versão antiga do systock..."
    rm -f $SYSTOCK_FILE
fi

# Criar o arquivo systock com o conteúdo do comando
cat << 'EOF' > $SYSTOCK_FILE

#!/bin/bash

# Variáveis globais
PENTAHO_PAN="/opt/pentaho/client-tools/data-integration/pan.sh"
PENTAHO_KITCHEN="/opt/pentaho/client-tools/data-integration/kitchen.sh"
ARQ="/opt/pentaho/client-tools/data-integration/integracoes"
PATH_SYSTOCK="integracao_auto"
# Cores ANSI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # Sem cor

# Função para exibir ajuda
function show_help() {
    echo -e "${YELLOW}Uso: systock [comando] [argumentos]${NC}"
    echo ""
    echo "Comandos disponíveis:"
    echo -e "  ${GREEN}integracao [nome]${NC}           - Executa a integração para o nome (nome pode ser 'diário', 'hora' para job ou qualquer outro para tabelas)"
    echo -e "  ${GREEN}limpar cache${NC}                - Limpa o cache"
    echo -e "  ${GREEN}verificar${NC}                   - Verifica os requisitos do servidor"
    echo -e "  ${GREEN}iniciar${NC}                     - Inicia os serviços do Pentaho e configura o arquivo kettle.properties"
    echo -e "  ${GREEN}base [criar|remover|restaurar]${NC} - Cria , remove ou restaura a base de dados e usuário 'systock'"
    echo -e "  ${GREEN}configurar-banco${NC}            - Configura o PostgreSQL para ser acessível externamente"
    echo -e "  ${GREEN}help${NC}                        - Exibe esta mensagem de ajuda"
}

# Função para restaurar
function restaurar_dump() {
    # Pergunta ao usuário a versão do dump
    read -p "Qual a versão do arquivo de importação? " version

    # Define o caminho do arquivo
    local dump_file="/tmp/systock_homolgado_v${version}.dmp"

    # Verifica se o arquivo existe
    if [[ ! -f "$dump_file" ]]; then
        echo -e "${RED}Arquivo $dump_file não encontrado.${NC}"
        return 1
    fi

    # Executa o pg_restore
    echo "Restaurando o banco de dados a partir de $dump_file..."
    pg_restore -v -d systock "$dump_file"

    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}Banco de dados restaurado com sucesso.${NC}"
    else
        echo -e "${RED}Falha ao restaurar o banco de dados.${NC}"
    fi
}

#Liberar Banco
function liberar_banco() {
    # Caminho dos arquivos de configuração do PostgreSQL
    local postgresql_conf="/etc/postgresql/16/main/postgresql.conf"
    local pg_hba_conf="/etc/postgresql/16/main/pg_hba.conf"
    local backup_postgresql_conf="/etc/postgresql/16/main/postgresql.conf.backup"
    local backup_pg_hba_conf="/etc/postgresql/16/main/pg_hba.conf.backup"

    # Verificando se os arquivos de configuração existem
    if [[ ! -f "$postgresql_conf" ]] || [[ ! -f "$pg_hba_conf" ]]; then
        echo -e "${RED}Arquivo de configuração não encontrado. Verifique a instalação do PostgreSQL e a versão especificada.${NC}"
        return 1
    fi

    # Fazendo backup dos arquivos de configuração
    echo "Criando backup dos arquivos de configuração..."
    [[ ! -f "$backup_postgresql_conf" ]] && cp "$postgresql_conf" "$backup_postgresql_conf"
    [[ ! -f "$backup_pg_hba_conf" ]] && cp "$pg_hba_conf" "$backup_pg_hba_conf"

    # Modificando postgresql.conf para permitir acessos externos
    echo "Modificando postgresql.conf para permitir acessos externos..."
    sed -i "s/^#listen_addresses = 'localhost'/listen_addresses = '*'/" "$postgresql_conf"
    if ! grep -q "listen_addresses = '\*'" "$postgresql_conf"; then
        echo -e "${RED}Falha ao modificar postgresql.conf. Restaurando backup...${NC}"
        cp "$backup_postgresql_conf" "$postgresql_conf"
        return 1
    fi

    # Modificando pg_hba.conf para permitir autenticação via MD5 de qualquer IP
    echo "Adicionando regra em pg_hba.conf para autenticação via MD5..."
    echo "host    all             all             0.0.0.0/0               md5" >> "$pg_hba_conf"
    if ! grep -q "host    all             all             0.0.0.0/0               md5" "$pg_hba_conf"; then
        echo -e "${RED}Falha ao adicionar regra em pg_hba.conf. Restaurando backup...${NC}"
        cp "$backup_pg_hba_conf" "$pg_hba_conf"
        return 1
    fi

    echo -e "${GREEN}Configurações alteradas com sucesso. Por favor, reinicie o serviço do PostgreSQL para aplicar as mudanças.${NC}"
}


# Função para executar a integração
function integracao() {
    local nome=$1

    if [[ -z "$nome" ]]; then
        echo -e "${RED}Erro: Nome é obrigatório para o comando 'integracao'${NC}"
        show_help
        exit 1
    fi

    if [[ "$nome" == 'diario' ]]; then
        integracao_tabela_job "$nome"
    elif [[ "$nome" == 'hora' ]]; then
        integracao_tabela_job "hora_hora"
    else
        integracao_tabela_task "$nome"
    fi
}

# Função para criar arquivo de configuração do Kettle
function criar_arquivo_kettle_properties() {
    local pasta="$HOME/.kettle"
    local arquivo="$pasta/kettle.properties"

    if [[ ! -f "$arquivo" ]]; then
        touch "$arquivo"
        echo "# Configurações do Kettle" >> "$arquivo"
    fi
}

# Função para executar a integração de jobs (Função adicionada)
function integracao_tabela_job() {
    local nome=$1
    if ! sh "$PENTAHO_KITCHEN" -file="$ARQ/${PATH_SYSTOCK}_job_${nome}.kjb"; then
        echo -e "${RED}Erro ao executar a integração de job: $nome${NC}"
        exit 1
    fi
}

# Função para executar a integração de tasks
function integracao_tabela_task() {
    local nome=$1
    if ! sh "$PENTAHO_PAN" -file="$ARQ/${PATH_SYSTOCK}_tabela_${nome}.ktr"; then
        echo -e "${RED}Erro ao executar a integração de task: $nome${NC}"
        exit 1
    fi
}

# Função para limpar o cache
function limpar_cache() {
    if ! sh "$PENTAHO_PAN" -file="$ARQ/limpar_cache.ktr"; then
        echo -e "${RED}Erro ao limpar o cache${NC}"
        exit 1
    fi
}

# Função para verificar os requisitos do servidor
function verificar_requisitos() {
    local mem_total=$(free -g | awk '/^Mem:/ { print $2 }')

    # Segunda tentativa caso a primeira falhe
    if [ -z "$mem_total" ] || [ "$mem_total" -eq 0 ]; then
        local mem_total=$(free -g | awk '/^Mem.:/ { print $2 }')
    fi

    # Tentativa usando /proc/meminfo se necessário
    if [ -z "$mem_total" ] || [ "$mem_total" -eq 0 ]; then
        # Captura a memória total em kB e converte para GB, assumindo que 1 GB = 1024 * 1024 kB
       local mem_total_kb=$(grep MemTotal /proc/meminfo | awk '{ print $2 }')
       local mem_total=$(echo "$mem_total_kb / 1024 / 1024" | bc)
    fi

    local hd_total=$(df -BG --total | grep 'total' | awk '{print $2}' | sed 's/G//')
    local num_cores=$(nproc)

    local mem_req=16
    local hd_req=500
    local mem_tolerancia=1
    local hd_tolerancia=80

    local erro=""

    if (( mem_total + mem_tolerancia < mem_req )); then
        erro+="Memória insuficiente: ${mem_total}GB. Requerido: ${mem_req}GB ou mais.\n"
    fi

    if (( hd_total + hd_tolerancia < hd_req )); then
        erro+="Espaço em disco insuficiente: ${hd_total}GB. Requerido: ${hd_req}GB ou mais.\n"
    fi

    if (( num_cores < 4 )); then
        erro+="Núcleos de processador insuficientes: ${num_cores}. Requerido: 4 ou mais.\n"
    fi

    if [[ -n "$erro" ]]; then
        echo -e "${RED}Requisitos não atendidos:${NC}\n${erro}"
    else
        echo -e "${GREEN}Todos os requisitos foram atendidos.${NC}"
        echo -e "${GREEN}Detalhes dos requisitos:${NC}"
        echo -e "Memória: ${mem_total}GB"
        echo -e "Espaço em disco: ${hd_total}GB"
        echo -e "Núcleos do processador: ${num_cores}"
    fi
}

function configura_kettle_properties() {
    # Define o caminho do diretório e do arquivo
    local dir_path="/home/systock/.kettle"
    local file_path="$dir_path/kettle.properties"
    local backup_path="$dir_path/kettle.properties.backup"

    # Verifica se o usuário atual é 'systock'
    if [ "$(whoami)" != "systock" ]; then
        echo -e "${RED}Erro: Este script só pode ser executado pelo usuário 'systock'.${NC}"
        exit 1
    fi

    # Cria o diretório .kettle se ele não existir
    if [ ! -d "$dir_path" ]; then
        echo "Criando diretório $dir_path..."
        mkdir -p "$dir_path"
    fi

    # Verifica se o arquivo kettle.properties existe e cria um backup
    if [ -f "$file_path" ]; then
        echo "Criando backup do arquivo existente em $backup_path..."
        cp "$file_path" "$backup_path"
    fi

    # Solicita os dados de origem do usuário
    read -p "Digite o host de origem: " origem_host
    read -p "Digite o nome do banco de dados de origem (Caminho): " origem_banco
    read -p "Digite o usuário de origem: " origem_usuario
    while true; do
        read -s -p "Digite a senha de origem: " origem_password
        echo
        read -s -p "Confirme a senha de origem: " password_confirm
        echo
        if [[ "$origem_password" == "$password_confirm" ]]; then
            break
        else
            echo "As senhas não correspondem. Tente novamente."
        fi
    done
    read -p "Digite a porta do banco de origem: " origem_port
    read -p "Digite o nome da empresa para o assunto do e-mail: " empresa

    # Verificação se o caminho é do tipo Windows
    if [[ "$origem_banco" =~ ^[a-zA-Z]:\\ ]]; then
        # Substitui cada barra invertida por quatro barras invertidas
        # Isso é necessário para que o 'echo' processe corretamente e exiba duas barras invertidas
        origem_banco="${origem_banco//\\/\\\\\\\\}"
    fi


    # Gera o conteúdo do arquivo kettle.properties
    {
        echo "caminho_integracoes=/opt/pentaho/client-tools/data-integration/integracoes/"
        echo "destino_host=localhost"
        echo "destino_banco=systock"
        echo "destino_usuario=systock"
        echo "destino_password=sys2017tock"
        echo "destino_port=5432"
        echo ""
        echo "origem_host=$origem_host"
        echo "origem_banco=$origem_banco"
        echo "origem_usuario=$origem_usuario"
        echo "origem_password=$origem_password"
        echo "origem_port=$origem_port"
        echo ""
        echo "email_integracao=integracao@systock.com.br"
        echo "email_autenticacao=Sys2022!"
        echo "email_assunto=Erro de Integracao Systock - $empresa"
        echo "email_destino=ti@systock.com.br"
        echo "email_destino_bc=mauro.lima@systock.com.br"
    } > "$file_path"

    echo -e "${GREEN}Arquivo kettle.properties configurado com sucesso.${NC}"
}

# Criar base
function criar_base() {
    sudo -u postgres psql -c "CREATE ROLE systock SUPERUSER LOGIN PASSWORD '123';"
    sudo -u postgres psql -c "CREATE DATABASE systock OWNER systock;"
    echo -e "${GREEN}Base de dados e usuário 'systock' criados com sucesso.${NC}"
}

# Remover base

function remover_base() {
    sudo -u postgres psql -c "DROP DATABASE IF EXISTS systock;"
    sudo -u postgres psql -c "DROP ROLE IF EXISTS systock;"
    echo -e "${GREEN}Base de dados e usuário 'systock' removidos com sucesso.${NC}"
}

# Verifica o comando passado
case "$1" in
    integracao)
        integracao "$2"
        ;;
    limpar)
        if [[ "$2" == "cache" ]]; then
            limpar_cache
        else
            echo -e "${RED}Comando inválido: $1 $2${NC}"
            show_help
            exit 1
        fi
        ;;
    verificar)
        verificar_requisitos
        ;;
    iniciar)
        configura_kettle_properties
        ;;
    base)
        case "$2" in
            criar)
                criar_base
                ;;
            remover)
                remover_base
                ;;
            restaurar)
                restaurar_dump
                ;;
            *)
                echo -e "${RED}Comando inválido para base: $2${NC}"
                show_help
                exit 1
                ;;
        esac
        ;;
    configurar-banco)
        liberar_banco
        ;;
    help|/help|-h|--help)
        show_help
        ;;
    *)
        echo -e "${RED}Comando inválido: $1${NC}"
        show_help
        exit 1
        ;;
esac
EOF

# Torna o arquivo executável
chmod +x $SYSTOCK_FILE

# Adiciona a função de autocomplete ao arquivo de configuração do shell
cat << 'EOF' >> ~/.bashrc

# Autocomplete para o comando systock
_systock_autocomplete() {
    local cur prev opts files
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Basic options for the main command
    if [[ "${COMP_CWORD}" == 1 ]]; then
        opts="integracao limpar verificar iniciar base configurar-banco help"
        COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
        return 0
    fi

    # Options for the 'integracao' sub-command
    if [[ "${prev}" == "integracao" ]]; then
        files=$(ls /opt/pentaho/client-tools/data-integration/integracoes/integracao_auto_job_*.kjb 2>/dev/null | xargs -n 1 basename | sed 's/integracao_auto_job_\(.*\)\.kjb/\1/')
        files+=" $(ls /opt/pentaho/client-tools/data-integration/integracoes/integracao_auto_tabela_*.ktr 2>/dev/null | xargs -n 1 basename | sed 's/integracao_auto_tabela_\(.*\)\.ktr/\1/')"

        if [[ -z "$files" ]]; then
            files="diario hora apoio produtos entradas consumos"
        fi
        
        COMPREPLY=( $(compgen -W "${files}" -- ${cur}) )
        return 0
    fi

    # Options for the 'limpar' sub-command
    if [[ "${prev}" == "limpar" ]]; then
        COMPREPLY=( $(compgen -W "cache" -- ${cur}) )
        return 0
    fi

    # Options for the 'base' sub-command
    if [[ "${prev}" == "base" ]]; then
        opts="criar remover restaurar"
        COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
        return 0
    fi

    # No further options required for 'verificar', 'iniciar', and 'configurar-banco' as they do not have subcommands
}

# Register the completion function
complete -F _systock_autocomplete systock
EOF


echo "${GREEN}O comando systock foi instalado e o autocomplete foi configurado.${NC}"
