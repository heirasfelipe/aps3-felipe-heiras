workspace "SAFELINE" "Dossiê de Arquitetura Viva — Sistema de Compliance, Segurança do Trabalho e Ergonomia (APS 3)" {

    model {
        # Pessoas (Atores Principais — alinhados ao C4 Nível 1 do projeto)
        tecnico = person "Técnico de Segurança" "Acompanha auditorias, valida ocorrências de segurança geradas pela IA, confirma NCs ou descarta falsos positivos."
        engenheiro = person "Engenheiro de Segurança" "Define perfis de segurança, políticas de compliance, limiares de monitoramento e acompanha indicadores."
        supervisor = person "Supervisor de Produção" "Consulta não conformidades confirmadas, gerencia planos de ação e registra execução das ações corretivas."

        # Sistemas Externos
        vms = softwareSystem "Sistema de Videomonitoramento (VMS)" "Disponibiliza fluxos contínuos de vídeo das câmeras dos postos de trabalho." "External"
        identidadeRh = softwareSystem "Sistema Corporativo de Identidade e RH" "Fornece autenticação corporativa (SSO/OIDC), usuários, papéis RBAC e estrutura organizacional." "External"
        notificacoes = softwareSystem "Serviço Corporativo de Notificações" "Entrega alertas corporativos multicanal (E-mail, Push, Teams) para Técnicos e Supervisores." "External"

        # Sistema Principal SAFELINE
        safeline = softwareSystem "SAFELINE" "Plataforma de auditoria em tempo real de EPIs e condições ergonômicas observáveis com validação humana." {

            portalWeb = container "Portal Web SafeLine" "Interface SPA para revisão de ocorrências com evidências anonimizadas, gestão de políticas e planos de ação." "React 18 / TypeScript / Vite" "WebBrowser"

            workerIa = container "Worker de Visão Computacional" "Consome streams RTSP do VMS, detecta ausência de EPIs e desvios ergonômicos observáveis (sem reconhecimento facial) e publica detecções." "Python 3.12 / YOLOv8 / OpenCV / ONNX"

            broker = container "Message Broker" "Barramento assíncrono de eventos com filas duráveis e Dead Letter Queues (DLQ) para desacoplar inferência, validação e alertas." "RabbitMQ 3.13 (AMQP 0-9-1)" "Queue"

            database = container "Banco de Dados Relacional" "Armazena perfis, políticas, detecções, ocorrências com controle de versão otimista, não conformidades e trilha de auditoria." "PostgreSQL 16" "Database"

            objectStorage = container "Object Storage de Evidências" "Armazena snapshots anonimizados de detecções com retenção controlada e acesso via URLs pré-assinadas." "MinIO (S3 API)" "Database"

            apiCore = container "API Core SafeLine" "Orquestra regras de compliance, máquina de estados da Ocorrência de Segurança, proteção contra concorrência e registro de NCs." "Python 3.12 / FastAPI / Pydantic v2" {

                ocorrenciaCtrl = component "OcorrenciaController" "Expõe endpoints REST de consulta de políticas, detalhamento e validação humana de ocorrências com autenticação JWT." "FastAPI APIRouter / Pydantic v2"

                politicaSvc = component "PoliticaComplianceService" "Gerencia perfis de segurança, políticas de monitoramento (limiares, debounce) e políticas de validação por posto." "Python Domain Service"

                ocorrenciaSvc = component "OcorrenciaService" "Consome detecções assíncronas, aplica debounce, gerencia a máquina de estados da OcorrênciaDeSeguranca e lock otimista." "Python Domain Service"

                ncSvc = component "NaoConformidadeService" "Registra NaoConformidade vinculada exclusivamente após confirmação humana e publica eventos para plano de ação." "Python Domain Service"

                repo = component "SafeLineRepository" "Persiste entidades de domínio e executa atualizações atômicas com controle de versão otimista no PostgreSQL 16." "SQLAlchemy Async / AsyncPG"

                brokerGateway = component "RabbitMQBroker" "Consome eventos de detecção e publica eventos de ocorrência criada, feedback de IA e não conformidade registrada." "aio-pika (AMQP 0-9-1)"

                storageGateway = component "ObjectStorageGateway" "Gera URLs pré-assinadas temporárias para exibição segura de evidências no Portal Web." "boto3 (HTTPS / S3 API)"

                notifGateway = component "NotificacaoGateway" "Despacha solicitações de alertas ao Serviço Corporativo de Notificações." "HTTPX Async (HTTPS / REST)"
            }
        }

        # Relacionamentos — Nível 1 e Nível 2
        tecnico -> portalWeb "Audita e valida ocorrências pendentes" "HTTPS"
        engenheiro -> portalWeb "Configura perfis, políticas e consulta indicadores" "HTTPS"
        supervisor -> portalWeb "Consulta não conformidades e gerencia planos de ação" "HTTPS"

        portalWeb -> identidadeRh "Autentica usuários via fluxo corporativo" "OIDC / OAuth 2.0"
        portalWeb -> ocorrenciaCtrl "Envia requisições de auditoria, políticas e validação" "HTTPS / REST + JSON + JWT"
        portalWeb -> objectStorage "Carrega imagens anonimizadas de evidência" "HTTPS / Pre-signed URL"

        workerIa -> vms "Consome fluxos contínuos de vídeo das câmeras" "RTSP / TCP (H.264)"
        workerIa -> ocorrenciaCtrl "Sincroniza políticas de monitoramento dos postos" "HTTPS / REST + JSON"
        workerIa -> objectStorage "Realiza upload de snapshots anonimizados (Claim Check)" "HTTPS / S3 API"
        workerIa -> broker "Publica DeteccaoRegistradaEventDTO" "AMQP 0-9-1 / JSON"

        # Relacionamentos — Nível 3 (Componentes da API Core)
        ocorrenciaCtrl -> identidadeRh "Valida assinatura de tokens JWT via JWKS" "HTTPS / JWKS"
        ocorrenciaCtrl -> politicaSvc "Consulta políticas de monitoramento e validação" "Chamada síncrona em memória"
        ocorrenciaCtrl -> ocorrenciaSvc "Delega consulta detalhada e validação humana" "Chamada síncrona em memória"

        brokerGateway -> broker "Consome detecções e publica eventos de domínio" "AMQP 0-9-1 / JSON"
        brokerGateway -> ocorrenciaSvc "Entrega DeteccaoRegistradaEventDTO para processamento" "Chamada assíncrona / Callback"

        ocorrenciaSvc -> politicaSvc "Avalia limiares e janela de debounce da política" "Chamada síncrona em memória"
        ocorrenciaSvc -> repo "Persiste detecção e transiciona Ocorrência com lock otimista" "Chamada síncrona em memória"
        ocorrenciaSvc -> storageGateway "Solicita URL pré-assinada da evidência" "Chamada síncrona em memória"
        ocorrenciaSvc -> ncSvc "Aciona geração de Não Conformidade quando decisao == CONFIRMAR" "Chamada síncrona em memória"
        ocorrenciaSvc -> brokerGateway "Publica OcorrenciaCriadaEventDTO ou FeedbackIAEventDTO" "Chamada assíncrona em memória"

        ncSvc -> repo "Persiste NaoConformidade vinculada à ocorrência" "Chamada síncrona em memória"
        ncSvc -> brokerGateway "Publica NaoConformidadeRegistradaEventDTO" "Chamada assíncrona em memória"

        politicaSvc -> repo "Consulta PerfilDeSeguranca e PoliticaDeMonitoramento" "Chamada síncrona em memória"
        repo -> database "Executa queries e transações ACID com versionamento" "TCP / PostgreSQL Wire Protocol"
        storageGateway -> objectStorage "Solicita URLs pré-assinadas de leitura" "HTTPS / S3 API"

        broker -> notifGateway "Encaminha eventos de alerta para entrega externa" "AMQP 0-9-1 / JSON"
        notifGateway -> notificacoes "Envia payload de alerta para Técnico ou Supervisor" "HTTPS / REST Webhook"
    }

    views {
        systemContext safeline "C4_N1_Contexto" "Diagrama de Contexto do Sistema SAFELINE (C4 Nível 1)" {
            include *
            autoLayout tb
        }

        container safeline "C4_N2_Containers" "Visão de Contêineres do SAFELINE (C4 Nível 2)" {
            include *
            autoLayout tb
        }

        component apiCore "C4_N3_Componentes_APICore" "Visão de Componentes da API Core SafeLine (C4 Nível 3)" {
            include *
            autoLayout tb
        }

        styles {
            element "Person" {
                shape Person
                background #f59e0b
                color #111827
            }
            element "Software System" {
                background #1e293b
                color #ffffff
            }
            element "External" {
                background #64748b
                color #ffffff
            }
            element "Container" {
                background #2563eb
                color #ffffff
            }
            element "Component" {
                background #0284c7
                color #ffffff
            }
            element "WebBrowser" {
                shape WebBrowser
                background #0ea5e9
                color #ffffff
            }
            element "Database" {
                shape Cylinder
                background #0f766e
                color #ffffff
            }
            element "Queue" {
                shape Pipe
                background #ea580c
                color #ffffff
            }
        }
    }
}

