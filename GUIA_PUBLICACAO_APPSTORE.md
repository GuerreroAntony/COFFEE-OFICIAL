# 📱 Guia Completo: Publicação COFFEE na App Store

> **Responsável:** Douglas Di Giglio (Apple Developer Account)  
> **App:** COFFEE - Assistente IA para alunos ESPM  
> **Bundle ID:** `com.leonardodigiglio.coffee`  
> **Data:** Março 2026

---

## 📋 Status da Implementação

✅ **Código preparado:**
- RevenueCat SDK 5.0+ integrado
- Product IDs definidos:
  - `com.coffee.cafe_com_leite.monthly` (R$29,90/mês)
  - `com.coffee.black.monthly` (R$49,90/mês)
- Branch: `feat/revenuecat-appstore`

⚠️ **Pendente (você precisa fazer):**
- [ ] Criar app no App Store Connect
- [ ] Criar produtos de assinatura
- [ ] Configurar RevenueCat Dashboard
- [ ] Substituir chaves de API no código
- [ ] Testar em sandbox
- [ ] Fazer archive e upload

---

## 🎯 Parte 1: App Store Connect

### 1.1 Criar o App

1. Acesse: https://appstoreconnect.apple.com
2. **Apps** → **+** → **New App**
3. Preencha:
   - **Platform:** iOS
   - **Name:** COFFEE
   - **Primary Language:** Portuguese (Brazil)
   - **Bundle ID:** `com.leonardodigiglio.coffee` (deve estar no Apple Developer)
   - **SKU:** `coffee-ios-2026` (identificador único interno)
   - **User Access:** Full Access

### 1.2 Criar Produtos de Assinatura

1. No app COFFEE → **Subscriptions** → **+** (Create Subscription Group)
2. **Subscription Group Reference Name:** `COFFEE Premium`
3. Dentro do grupo, criar 2 produtos:

#### Produto 1: Café com Leite

- **Product ID:** `com.coffee.cafe_com_leite.monthly`
- **Reference Name:** Café com Leite Monthly
- **Subscription Duration:** 1 Month
- **Price:** R$ 29,90 (escolher tier equivalente)
- **Localization (pt-BR):**
  - **Display Name:** Café com Leite
  - **Description:** Plano mensal com funcionalidades essenciais do COFFEE

#### Produto 2: Black

- **Product ID:** `com.coffee.black.monthly`
- **Reference Name:** Black Monthly
- **Subscription Duration:** 1 Month
- **Price:** R$ 49,90 (escolher tier equivalente)
- **Localization (pt-BR):**
  - **Display Name:** Black
  - **Description:** Plano mensal completo com todas as funcionalidades premium

### 1.3 Configurar Trial

1. Em cada produto → **Subscription Prices**
2. Ativar **Introductory Offer:**
   - **Free Trial:** 7 days
   - **Elegibilidade:** New Subscribers Only

---

## 🔧 Parte 2: RevenueCat Dashboard

### 2.1 Criar Conta RevenueCat

1. Acesse: https://app.revenuecat.com/signup
2. Crie conta com email Apple Developer
3. Criar novo projeto: **COFFEE**

### 2.2 Configurar App iOS

1. **Project Settings** → **Apps** → **+ New**
2. Preencha:
   - **App Name:** COFFEE iOS
   - **Bundle ID:** `com.leonardodigiglio.coffee`
   - **Platform:** iOS
   - **App Store Connect API Key:** (criar no próximo passo)

### 2.3 Conectar com App Store Connect

#### Gerar App Store Connect API Key

1. App Store Connect → **Users and Access** → **Integrations** → **App Store Connect API**
2. **Generate API Key:**
   - **Name:** RevenueCat COFFEE
   - **Access:** App Manager
3. **Download** o arquivo `.p8`
4. Copiar **Issuer ID** e **Key ID**

#### Configurar no RevenueCat

1. RevenueCat Dashboard → **COFFEE** → **App Store Connect**
2. Upload:
   - **Issuer ID**
   - **Key ID**
   - **Private Key** (conteúdo do arquivo `.p8`)
3. **Save**

### 2.4 Criar Entitlements e Offerings

#### Criar Entitlements (permissões)

1. **RevenueCat Dashboard** → **Entitlements** → **+ New**
2. Criar:
   - **ID:** `premium`
   - **Display Name:** Premium Access

#### Criar Offering (pacotes)

1. **Offerings** → **+ New Offering**
2. **Identifier:** `default` (padrão)
3. **Add Package:**
   - **Package 1:**
     - **Identifier:** `cafe_com_leite`
     - **Product:** `com.coffee.cafe_com_leite.monthly`
     - **Entitlement:** `premium`
   - **Package 2:**
     - **Identifier:** `black`
     - **Product:** `com.coffee.black.monthly`
     - **Entitlement:** `premium`

### 2.5 Copiar API Keys

1. **Project Settings** → **API Keys**
2. Copiar:
   - **Public Apple SDK Key** (começa com `appl_`)

**⚠️ GUARDE ESSA CHAVE - você vai precisar no código!**

---

## 💻 Parte 3: Atualizar Código iOS

### 3.1 Substituir API Key

Abra `coffee-frontend/COFFEEApp.swift` e substitua:

```swift
// ANTES (placeholder)
let apiKey = "appl_XXXXXXXXXXXXXXX"

// DEPOIS (sua chave real do RevenueCat)
let apiKey = "appl_SuaChaveRealAqui"
```

### 3.2 Commit e Push

```bash
cd /Users/douglasdigigliomillan/GitHub/COFFEE-OFICIAL
git add coffee-frontend/COFFEEApp.swift
git commit -m "chore: adicionar chave RevenueCat real"
git push origin feat/revenuecat-appstore
```

---

## 🧪 Parte 4: Teste em Sandbox

### 4.1 Criar Usuário Sandbox

1. App Store Connect → **Users and Access** → **Sandbox Testers**
2. **+** → Criar usuário teste:
   - Email: `teste.coffee@icloud.com` (exemplo)
   - Senha: escolher
   - Country/Region: Brazil

### 4.2 Configurar iPhone

1. iPhone → **Settings** → **App Store** → **Sandbox Account**
2. Login com usuário sandbox criado

### 4.3 Testar Compra

1. Abrir Xcode
2. **Product** → **Scheme** → **COFFEE**
3. Selecionar seu iPhone físico
4. **Product** → **Run** (▶️)
5. No app:
   - Ir para tela de assinatura
   - Tentar comprar "Café com Leite" ou "Black"
   - Confirmar compra (não será cobrado - sandbox)
6. Verificar logs no Xcode:
   ```
   ✅ RevenueCat configurado com sucesso
   ✅ Produtos carregados do RevenueCat: 2 pacotes
   ✅ Compra realizada com sucesso: Black
   ```

---

## 📦 Parte 5: Archive e Upload

### 5.1 Preparar Versão

1. Xcode → COFFEE.xcodeproj
2. Target COFFEE → **General**
3. Verificar:
   - **Version:** 1.0
   - **Build:** 1
   - **Deployment Target:** iOS 17.0

### 5.2 Configurar Signing

1. **Signing & Capabilities**
2. **Team:** Selecionar seu Apple Developer Account
3. **Automatically manage signing:** ✅
4. Verificar que **Provisioning Profile** foi gerado

### 5.3 Archive

1. **Product** → **Destination** → **Any iOS Device (arm64)**
2. **Product** → **Archive**
3. Aguardar build (pode demorar 5-10 min)
4. Quando terminar, abre o **Organizer**

### 5.4 Upload para App Store Connect

1. No **Organizer** → Selecionar archive
2. **Distribute App** → **App Store Connect** → **Upload**
3. Opções:
   - **Include bitcode:** NO
   - **Upload symbols:** YES
   - **Manage Version and Build Number:** YES (Xcode gerencia automaticamente)
4. **Upload**
5. Aguardar processamento (15-30 min)

---

## 📝 Parte 6: Submeter para Revisão

### 6.1 Preencher Metadata

1. App Store Connect → COFFEE → **1.0 Prepare for Submission**
2. Preencher:

#### Screenshots (obrigatório)
- 6.7" (iPhone 15 Pro Max): 3-10 screenshots
- 6.5" (iPhone 14 Plus): 3-10 screenshots  
- 5.5" (iPhone 8 Plus): 3-10 screenshots

**Dica:** Use Simulator + `⌘+S` para capturar

#### App Information
- **Name:** COFFEE
- **Subtitle:** Assistente IA para alunos ESPM
- **Category:** Education
- **Age Rating:** 4+

#### Description (pt-BR)
```
Grave suas aulas e tenha um assistente IA que responde perguntas baseado nas transcrições e materiais do Canvas ESPM.

RECURSOS:
• Transcrição automática on-device (WhisperKit)
• Assistente IA "Barista" com respostas fundamentadas
• Integração com Canvas ESPM
• Live Activities com Dynamic Island
• Gravação em background

PLANOS:
• Café com Leite: R$29,90/mês (funcionalidades essenciais)
• Black: R$49,90/mês (todas as funcionalidades)
• Trial grátis: 7 dias

Perfeito para estudantes que querem aproveitar melhor suas aulas.
```

#### Keywords (pt-BR)
```
aulas, transcrição, IA, assistente, ESPM, estudante, gravação, Canvas
```

#### Support URL
```
https://coffee-oficial-production.up.railway.app
```

#### Privacy Policy URL
```
https://coffee-oficial-production.up.railway.app/privacy
```

### 6.2 Configurar App Privacy

1. **App Privacy** → **Get Started**
2. Responder sobre coleta de dados:
   - **Email Address:** YES (para login)
   - **Audio Data:** YES (para gravações)
   - **Usage Data:** YES (analytics)

### 6.3 Submeter

1. Selecionar build enviado
2. **Export Compliance:** No (não usa criptografia exportável)
3. **Add for Review**
4. **Submit for Review**

⏱️ **Tempo de revisão:** 1-7 dias

---

## 🎯 Próximos Passos Após Aprovação

1. **TestFlight** (opcional antes de publicar):
   - Convidar beta testers
   - Testar em produção real
   - Coletar feedback

2. **Release:**
   - App Store Connect → **Release this version**
   - Escolher data de lançamento

3. **Marketing:**
   - Preparar posts para redes sociais
   - Compartilhar com alunos ESPM

---

## 🚨 Checklist Final

Antes de submeter, verificar:

- [ ] Produtos de assinatura configurados no App Store Connect
- [ ] RevenueCat conectado com App Store Connect
- [ ] API Key do RevenueCat atualizada no código
- [ ] Testado compra em sandbox
- [ ] Screenshots preparados (3 tamanhos)
- [ ] Metadata preenchida (descrição, keywords)
- [ ] Privacy Policy disponível
- [ ] Build uploaded e processado
- [ ] Versão 1.0 Build 1 selecionada

---

## 📞 Suporte

**Dúvidas sobre código:**
- Leo (desenvolvedor)

**Dúvidas sobre publicação:**
- Douglas (Apple Developer Account)

**Docs oficiais:**
- RevenueCat: https://docs.revenuecat.com
- App Store Connect: https://developer.apple.com/app-store-connect/

---

✅ **Boa sorte com a publicação!** 🚀
