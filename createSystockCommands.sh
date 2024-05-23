#!/bin/bash

# Variáveis para o script systock
SYSTOCK_FILE="/usr/local/bin/systock"

# Criar o arquivo systock com o conteúdo do comando
cat << 'EOF' > $SYSTOCK_FILE
#!/bin/bash

# Variáveis globais
PENTAHO_PAN="/opt/pentaho/client-tools/data-integration/pan.sh"
PENTAHO_KITCHEN="/opt/pentaho/client-tools/data-integration/kitchen.sh"
ARQ="/opt/pentaho/client-tools/data-integration/integracoes"

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
    echo -e "  ${GREEN}integracao [nome]${NC}           - Executa a integração para o nome (nome pode ser 'diario', 'hora' para job ou qualquer outro para tabelas)"
    echo -e "  ${GREEN}limpar cache${NC}                - Limpa o cache"
    echo -e "  ${GREEN}verificar${NC}                   - Verifica os requisitos do servidor"
    echo -e "  ${GREEN}help${NC}                        - Exibe esta mensagem de ajuda"
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
    if ! sh "$PENTAHO_KITCHEN" -file="$ARQ/integracao_winthor_job_${nome}.kjb"; then
        echo -e "${RED}Erro ao executar a integração de job: $nome${NC}"
        exit 1
    fi
}

# Função para executar a integração de tasks
function integracao_tabela_task() {
    local nome=$1
    if ! sh "$PENTAHO_PAN" -file="$ARQ/integracao_winthor_tabela_${nome}.ktr"; then
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
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    case "${COMP_CWORD}" in
        2)
            opts="integracao limpar verificar help"
            COMPREPLY=( $(compgen -W "${opts}" -- ${cur}) )
            return 0
            ;;
        3)
            if [[ "${prev}" == "integracao" ]]; then
                files=$(ls /opt/pentaho/client-tools/data-integration/integracoes/integracao_auto_job_*.kjb 2>/dev/null | xargs -n 1 basename | sed 's/integracao_auto_job_\(.*\)\.kjb/\1/')
                files+=" $(ls /opt/pentaho/client-tools/data-integration/integracoes/integracao_auto_tabela_*.ktr 2>/dev/null | xargs -n 1 basename | sed 's/integracao_auto_tabela_\(.*\)\.ktr/\1/')"
                COMPREPLY=( $(compgen -W "${files}" -- ${cur}) )
                return 0
            fi
            if [[ "${prev}" == "limpar" ]]; then
                COMPREPLY=( $(compgen -W "cache" -- ${cur}) )
                return 0
            fi
            ;;
    esac
}

complete -F _systock_autocomplete systock
EOF

# Recarregar as configurações do shell
source ~/.bashrc

echo -e "${GREEN}O comando systock foi instalado e o autocomplete foi configurado.${NC}"
