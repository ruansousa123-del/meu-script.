-- LocalScript: StarterPlayer > StarterPlayerScripts
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

----------------------------------------------------------------
-- SESSÃO ÚNICA: ao rodar de novo, apaga o que as versões antigas criaram
-- e faz a cópia antiga parar (as cópias muito antigas só param ao reentrar no jogo)
----------------------------------------------------------------
local SESSAO = {}

local function limparTudo()
	local pg = Players.LocalPlayer:FindFirstChild("PlayerGui")
	if pg then
		for _, g in ipairs(pg:GetChildren()) do
			if g.Name == "ESPControle" or g.Name == "ESPJanela" or g.Name == "ESPErro" then g:Destroy() end
		end
	end
	for _, f in ipairs(workspace:GetChildren()) do
		if f.Name == "ESPEsqueleto" then f:Destroy() end
	end
	for _, d in ipairs(workspace:GetDescendants()) do
		if (d.Name == "ESPItem" and d:IsA("BoxHandleAdornment"))
			or (d.Name == "NomeItem" and d:IsA("BillboardGui")) then
			d:Destroy()
		end
	end
end

limparTudo()
shared.ESP_FECHAR = limparTudo
shared.ESP_SESSAO = SESSAO

local TRANSPARENCIA = 0.5
local INTERACAO_RAPIDA = true
local ESP_LIGADO = true

local TAMANHO_MAXIMO = 4
local TAMANHO_MAXIMO_NOME = 8

----------------------------------------------------------------
-- RARIDADES (edite as palavras para o seu jogo)
-- Prioridade: 1) Attribute/Value "Rarity" ou "Raridade" no objeto
--             2) palavras no nome do objeto (do mítico para baixo)
--             3) se nada bater, é comum
----------------------------------------------------------------
local RARIDADES = {
	{ id = "comum",    rotulo = "COMUM",    sigla = "C", cor = Color3.fromRGB(255, 255, 255), palavras = {} },
	{ id = "incomum",  rotulo = "INCOMUM",  sigla = "I", cor = Color3.fromRGB(60, 220, 90),
		palavras = { "extintor", "extinguisher", "radio", "rádio", "tablet", "camera", "câmera", "uncommon", "incomum" } },
	{ id = "raro",     rotulo = "RARO",     sigla = "R", cor = Color3.fromRGB(170, 80, 255),
		palavras = { "celular", "phone", "telefone", "rare", "raro" } },
	{ id = "lendário", rotulo = "LENDÁRIO", sigla = "L", cor = Color3.fromRGB(255, 230, 0),
		palavras = { "notebook", "laptop", "computador", "computer", "diamond", "diamante", "legendary", "lendario", "lendário" } },
	{ id = "mítico",   rotulo = "MÍTICO",   sigla = "M", cor = Color3.fromRGB(255, 50, 50),
		palavras = { "mythic", "mythical", "mitico", "mítico", "ouro", "gold" } },
}

local ALIAS = {
	comum = "comum", common = "comum",
	incomum = "incomum", uncommon = "incomum",
	raro = "raro", rare = "raro",
	lendario = "lendário", ["lendário"] = "lendário", legendary = "lendário",
	mitico = "mítico", ["mítico"] = "mítico", mythic = "mítico", mythical = "mítico",
}

local POR_ID = {}
local ativos = {} -- filtro: quais raridades aparecem
for _, r in ipairs(RARIDADES) do
	POR_ID[r.id] = r
	ativos[r.id] = true
end

-- Nomes que contam como item (as palavras das raridades entram automaticamente)
local NOMES_ITEM = {
	"chave", "key", "cartao", "cartão", "keycard", "bateria", "battery",
	"pen", "usb", "hd", "disco", "disk", "lanterna", "flashlight",
	"documento", "document", "papel", "paper", "nota", "note", "item", "loot", "pc",
}
for _, r in ipairs(RARIDADES) do
	for _, p in ipairs(r.palavras) do table.insert(NOMES_ITEM, p) end
end

local IGNORAR = {
	"wall", "parede", "floor", "chao", "chão", "piso", "ceiling", "teto", "baseplate", "terrain",
	"door", "porta", "button", "botao", "botão", "lever", "alavanca", "switch",
	"gate", "portao", "portão", "elevator", "elevador", "window", "janela", "stair", "escada",
	"armario", "armário", "locker", "wardrobe", "closet", "cabinet", "cupboard", "gabinete",
	"guarda-roupa", "guardaroupa", "print",
}

local marcados = {}
local elementos = {}
local contador = 0
local atualizarBotao

----------------------------------------------------------------
-- Auxiliares
----------------------------------------------------------------
local function contem(texto, lista)
	texto = string.lower(texto or "")
	for _, p in ipairs(lista) do
		if string.find(texto, p, 1, true) then return true end
	end
	return false
end

local function maiorLado(v)
	return math.max(v.X, v.Y, v.Z)
end

local function tamanhoDe(obj)
	if obj:IsA("BasePart") then return obj.Size end
	if obj:IsA("Model") then return obj:GetExtentsSize() end
	return nil
end

local function nomeIgnorado(obj)
	if contem(obj.Name, IGNORAR) then return true end
	if obj.Parent and obj.Parent ~= workspace and contem(obj.Parent.Name, IGNORAR) then return true end
	return false
end

local function raridadeDe(obj)
	for _, chave in ipairs({ "Rarity", "Raridade" }) do
		local v = obj:GetAttribute(chave)
		if v == nil then
			local c = obj:FindFirstChild(chave)
			if c and c:IsA("ValueBase") then v = c.Value end
		end
		if v ~= nil then
			local id = ALIAS[string.lower(tostring(v))]
			if id then return POR_ID[id] end
		end
	end
	for i = #RARIDADES, 2, -1 do
		if contem(obj.Name, RARIDADES[i].palavras) then return RARIDADES[i] end
	end
	return RARIDADES[1]
end

local function resolverAlvo(prompt)
	local alvo = prompt.Parent
	if alvo and alvo:IsA("Attachment") then alvo = alvo.Parent end
	if alvo and alvo:IsA("BasePart") then
		local m = alvo.Parent
		if m and m:IsA("Model") and m ~= workspace then
			if maiorLado(m:GetExtentsSize()) <= TAMANHO_MAXIMO_NOME then
				alvo = m
			end
		end
	end
	return alvo
end

local function pegarPartes(obj)
	if obj:IsA("BasePart") then return { obj } end
	if obj:IsA("Tool") then
		local h = obj:FindFirstChild("Handle")
		return h and { h } or {}
	end
	local lista = {}
	for _, p in ipairs(obj:GetDescendants()) do
		if p:IsA("BasePart") and maiorLado(p.Size) <= TAMANHO_MAXIMO_NOME then
			table.insert(lista, p)
		end
	end
	return lista
end

local function ehItem(obj)
	if obj:IsA("Tool") then return true end
	if nomeIgnorado(obj) then return false end
	local tam = tamanhoDe(obj)
	if not tam then return false end
	local lado = maiorLado(tam)
	if contem(obj.Name, NOMES_ITEM) or obj:GetAttribute("Rarity") ~= nil or obj:GetAttribute("Raridade") ~= nil then
		return lado <= TAMANHO_MAXIMO_NOME
	end
	return lado <= TAMANHO_MAXIMO
end

----------------------------------------------------------------
-- Marcação
----------------------------------------------------------------
local function lerNumero(obj, nomes)
	for _, n in ipairs(nomes) do
		local v = obj:GetAttribute(n)
		if type(v) == "number" then return v end
		local c = obj:FindFirstChild(n)
		if c and c:IsA("ValueBase") and type(c.Value) == "number" then return c.Value end
	end
	return nil
end

local function pesoDe(obj)
	return lerNumero(obj, { "Weight", "weight", "Peso", "peso", "Mass" })
end

local function valorDe(obj)
	return lerNumero(obj, { "Value", "value", "Valor", "valor", "Price", "price", "Preco", "Worth", "Money", "Cash" })
end

local function marcar(obj, tentativa)
	if not ESP_LIGADO then return end
	tentativa = tentativa or 0
	if not obj or marcados[obj] or not obj.Parent then return end
	if obj.Parent:FindFirstChildOfClass("Humanoid") then return end

	local partes = pegarPartes(obj)
	if #partes == 0 then
		if tentativa < 5 then task.delay(1, marcar, obj, tentativa + 1) end
		return
	end

	if not ehItem(obj) then return end

	local raridade = raridadeDe(obj)
	if not ativos[raridade.id] then return end

	marcados[obj] = true
	contador += 1

	for _, parte in ipairs(partes) do
		local box = Instance.new("BoxHandleAdornment")
		box.Name = "ESPItem"
		box.Adornee = parte
		box.Size = parte.Size
		box.Color3 = raridade.cor
		box.Transparency = TRANSPARENCIA
		box.AlwaysOnTop = true
		box.ZIndex = 1
		box.Parent = parte
		table.insert(elementos, box)
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "NomeItem"
	gui.Adornee = partes[1]
	gui.Size = UDim2.fromOffset(240, 36)
	gui.StudsOffset = Vector3.new(0, 2, 0)
	gui.AlwaysOnTop = true
	gui.Parent = partes[1]
	table.insert(elementos, gui)

	local txt = Instance.new("TextLabel")
	txt.Size = UDim2.fromScale(1, 1)
	txt.BackgroundTransparency = 1
	local extra = ""
	local peso, valor = pesoDe(obj), valorDe(obj)
	if peso then extra = extra .. " · " .. peso .. "kg" end
	if valor then extra = extra .. " · $" .. valor end
	txt.Text = "[" .. raridade.rotulo .. "] " .. obj.Name .. extra
	txt.TextColor3 = raridade.cor
	txt.TextStrokeTransparency = 0
	txt.Font = Enum.Font.GothamBold
	txt.TextScaled = true
	txt.Parent = gui

	if atualizarBotao then atualizarBotao() end
end

local function verificar(obj)
	if not ESP_LIGADO then return end
	if obj:IsA("Tool") then
		marcar(obj)
	elseif obj:IsA("ProximityPrompt") then
		-- prompts de esconder/entrar (armários etc.) não são item
		local TEXTOS_IGNORAR = { "esconder", "hide", "entrar", "enter", "armario", "armário", "locker" }
		if contem(obj.ActionText, TEXTOS_IGNORAR) or contem(obj.ObjectText, TEXTOS_IGNORAR)
			or contem(obj.ActionText, IGNORAR) or contem(obj.ObjectText, IGNORAR) then
			return
		end
		local alvo = resolverAlvo(obj)
		if not alvo or not ehItem(alvo) then return end
		marcar(alvo)
	elseif obj:IsA("ClickDetector") then
		local alvo = obj.Parent
		if alvo and alvo:IsA("BasePart") and alvo.Parent and alvo.Parent:IsA("Model")
			and alvo.Parent ~= workspace and maiorLado(alvo.Parent:GetExtentsSize()) <= TAMANHO_MAXIMO_NOME then
			alvo = alvo.Parent
		end
		if alvo and ehItem(alvo) then marcar(alvo) end
	end
end

local tokenScan = 0
local function escanear()
	tokenScan += 1
	local meu = tokenScan
	local n = 0
	for _, obj in ipairs(workspace:GetDescendants()) do
		local c = obj.ClassName
		if c == "ProximityPrompt" or c == "ClickDetector" or c == "Tool" then
			pcall(verificar, obj)
		end
		n += 1
		if n % 4000 == 0 then
			task.wait()
			if tokenScan ~= meu or not ESP_LIGADO then return end
		end
	end
	for _, obj in ipairs(CollectionService:GetTagged("Item")) do
		pcall(marcar, obj)
	end
end

local function limpar()
	for _, e in ipairs(elementos) do
		if e then e:Destroy() end
	end
	table.clear(elementos)
	table.clear(marcados)
	contador = 0
end

local function reescanear()
	limpar()
	if ESP_LIGADO then escanear() end
	if atualizarBotao then atualizarBotao() end
end

local function alternar()
	ESP_LIGADO = not ESP_LIGADO
	reescanear()
end

----------------------------------------------------------------
-- INSTANT PP: todos os ProximityPrompts instantâneos (independe do ESP)
----------------------------------------------------------------
local INSTANT_PP = INTERACAO_RAPIDA
local holdOriginal = setmetatable({}, { __mode = "k" })
local vigiados = setmetatable({}, { __mode = "k" })

local function aplicarInstant(prompt)
	if not prompt:IsA("ProximityPrompt") then return end
	if not vigiados[prompt] then
		vigiados[prompt] = true
		-- se o jogo tentar devolver o tempo de segurar, zera de novo
		prompt:GetPropertyChangedSignal("HoldDuration"):Connect(function()
			if INSTANT_PP and prompt.HoldDuration ~= 0 then
				holdOriginal[prompt] = prompt.HoldDuration
				prompt.HoldDuration = 0
			end
		end)
	end
	if INSTANT_PP and prompt.HoldDuration ~= 0 then
		holdOriginal[prompt] = prompt.HoldDuration
		prompt.HoldDuration = 0
	end
end

local function escanearInstant()
	local n = 0
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj.ClassName == "ProximityPrompt" then pcall(aplicarInstant, obj) end
		n += 1
		if n % 4000 == 0 then task.wait() end
	end
end

local function restaurarInstant()
	for prompt, original in pairs(holdOriginal) do
		if prompt.Parent then prompt.HoldDuration = original end
	end
	table.clear(holdOriginal)
end

----------------------------------------------------------------
-- ESQUELETO: players e monstros (usa os Motor6D do corpo, serve p/ qualquer rig)
----------------------------------------------------------------
local RunService = game:GetService("RunService")
local eu = Players.LocalPlayer

local COR_PLAYER = Color3.fromRGB(0, 255, 255)
local COR_MONSTRO = Color3.fromRGB(255, 50, 50)
local ESPESSURA = 0.12
local SKEL_PLAYERS = true
local SKEL_MONSTROS = true

-- ESP de players: botão geral "Ativar ESP" (começa DESLIGADO)
local ESP_PLAYERS_ON = false
local ESP_NOME = true
local ESP_SKEL = true
local fpsBaixo = false        -- ligado sozinho quando o FPS cai (reduz a taxa de atualização)
local escondidoTudo = true    -- evita reprocessar quando o ESP está desligado

-- false = ignora bonecos/NPCs (só jogadores entram; o monstro é um jogador)
local MOSTRAR_NPCS = false
local OTIMIZAR = false   -- true = esqueleto atualiza a cada 2 quadros
local SKEL_DIST = 0      -- 0 = sem limite; senão, só desenha esqueleto até essa distância

-- Modelos SEM Humanoid só viram "monstro" se o nome tiver uma dessas palavras
local PALAVRAS_MONSTRO = {
	"monster", "monstro", "enemy", "inimigo", "killer", "beast", "creature",
	"zombie", "zumbi", "entity", "entidade", "demon", "demonio", "demônio",
}

local esqueletos = {}
local pastaSkel = Instance.new("Folder")
pastaSkel.Name = "ESPEsqueleto"
pastaSkel.Parent = workspace

-- Jogadores que você quer forçar como MONSTRO (nome de usuário), ex: { "NomeAqui" }
local MONSTROS_NOMES = {}

local function textoMonstro(v)
	return type(v) == "string" and contem(v, PALAVRAS_MONSTRO)
end

-- Escolha manual (pelo painel) e detecção automática do monstro entre os jogadores
local MONSTROS_MANUAL = {}   -- [NomeDeUsuario] = true
local AUTO_DETECTAR = true
local cacheAuto, cacheAutoT = {}, 0

-- O monstro é UM jogador com corpo diferente dos outros (altura ou quantidade de juntas).
-- Só aceita se houver exatamente 1 jogador "diferente".
local function calcularAuto()
	if os.clock() - cacheAutoT < 1 then return end
	cacheAutoT = os.clock()
	cacheAuto = {}
	local lista = {}
	for _, j in ipairs(Players:GetPlayers()) do
		local c = j.Character
		local hum = c and c.Parent and c:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			local n = 0
			for _, d in ipairs(c:GetDescendants()) do
				if d:IsA("Motor6D") then n += 1 end
			end
			table.insert(lista, { j = j, h = c:GetExtentsSize().Y, n = n })
		end
	end
	if #lista < 3 then return end

	local alturas = {}
	for _, x in ipairs(lista) do table.insert(alturas, x.h) end
	table.sort(alturas)
	local mediana = alturas[math.ceil(#alturas / 2)]

	local freq, moda, modaN = {}, 0, 0
	for _, x in ipairs(lista) do
		freq[x.n] = (freq[x.n] or 0) + 1
		if freq[x.n] > modaN then moda, modaN = x.n, freq[x.n] end
	end

	local suspeitos = {}
	for _, x in ipairs(lista) do
		if x.h >= mediana * 1.4 or x.h <= mediana * 0.6 or math.abs(x.n - moda) >= 5 then
			table.insert(suspeitos, x.j)
		end
	end
	if #suspeitos == 1 then cacheAuto[suspeitos[1]] = true end
end

-- Times que NUNCA são o monstro (espectadores, lobby...)
local PALAVRAS_TIME_IGNORAR = { "spectat", "espect", "observ", "lobby", "dead", "morto", "neutral", "neutro" }
local cacheMenor, cacheTempo = nil, 0

-- Se o jogo tem 2+ times, o MENOR time (sem empate) é o do monstro
local function timeMonstro()
	if os.clock() - cacheTempo < 0.5 then return cacheMenor end
	cacheTempo = os.clock()
	cacheMenor = nil
	local contagem = {}
	for _, j in ipairs(Players:GetPlayers()) do
		local t = j.Team
		if t and not contem(t.Name, PALAVRAS_TIME_IGNORAR) then
			contagem[t] = (contagem[t] or 0) + 1
		end
	end
	local nTimes, menor, menorN, empate = 0, nil, math.huge, false
	for t, n in pairs(contagem) do
		nTimes += 1
		if n < menorN then
			menor, menorN, empate = t, n, false
		elseif n == menorN then
			empate = true
		end
	end
	if nTimes >= 2 and not empate then cacheMenor = menor end
	return cacheMenor
end

-- Um JOGADOR é monstro se: nome na lista, time, atributos, nome do modelo ou DisplayName tiver as palavras
local function ehMonstroJogador(model, jogador, hum)
	if contem(model.Name, PALAVRAS_MONSTRO) then return true end
	if hum and contem(hum.DisplayName, PALAVRAS_MONSTRO) then return true end
	if jogador then
		if MONSTROS_MANUAL[jogador.Name] then return true end
		if AUTO_DETECTAR then
			calcularAuto()
			if cacheAuto[jogador] then return true end
		end
		for _, n in ipairs(MONSTROS_NOMES) do
			if string.lower(n) == string.lower(jogador.Name) then return true end
		end
		if contem(jogador.DisplayName, PALAVRAS_MONSTRO) then return true end
		if jogador.Team and contem(jogador.Team.Name, PALAVRAS_MONSTRO) then return true end
		if jogador.Team and jogador.Team == timeMonstro() then return true end
		for _, v in pairs(jogador:GetAttributes()) do
			if textoMonstro(v) then return true end
		end
	end
	for _, v in pairs(model:GetAttributes()) do
		if textoMonstro(v) then return true end
	end
	return false
end

local function definirTipo(dados, tipo)
	dados.tipo = tipo
	dados.cor = (tipo == "player") and COR_PLAYER or COR_MONSTRO
	for _, box in pairs(dados.motores) do box.Color3 = dados.cor end
	if dados.txt then dados.txt.TextColor3 = dados.cor end
end

local function adicionarOsso(dados, motor)
	if dados.motores[motor] then return end
	if not motor.Part0 or not motor.Part1 then return end
	local box = Instance.new("BoxHandleAdornment")
	box.Name = "Osso"
	box.AlwaysOnTop = true
	box.ZIndex = 5
	box.Transparency = 0
	box.Color3 = dados.cor
	box.Size = Vector3.new(ESPESSURA, ESPESSURA, 0.1)
	box.Visible = false
	box.Parent = pastaSkel
	dados.motores[motor] = box
end

local function criarLabel(dados, model)
	local alvo = model:FindFirstChild("Head") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not alvo then return end
	local gui = Instance.new("BillboardGui")
	gui.Name = "NomeSkel"
	gui.Adornee = alvo
	gui.Size = UDim2.fromOffset(260, 36)
	gui.StudsOffset = Vector3.new(0, 2.2, 0)
	gui.AlwaysOnTop = true
	gui.Parent = pastaSkel

	local txt = Instance.new("TextLabel")
	txt.Size = UDim2.fromScale(1, 1)
	txt.BackgroundTransparency = 1
	txt.TextColor3 = dados.cor
	txt.TextStrokeTransparency = 0
	txt.Font = Enum.Font.GothamBold
	txt.TextScaled = true
	txt.Parent = gui

	dados.gui, dados.txt, dados.alvo = gui, txt, alvo
end

local function destruirEsqueleto(model)
	local dados = esqueletos[model]
	if not dados then return end
	if dados.conexao then dados.conexao:Disconnect() end
	for _, box in pairs(dados.motores) do box:Destroy() end
	if dados.gui then dados.gui:Destroy() end
	if dados.hl then dados.hl:Destroy() end
	esqueletos[model] = nil
end

local function criarEsqueleto(model, tipo, nome, humanoid, jogador)
	if esqueletos[model] then return end
	local dados = {
		jogador = jogador,
		tipo = tipo,
		nome = nome,
		humanoid = humanoid,
		motores = {},
		cor = (tipo == "player") and COR_PLAYER or COR_MONSTRO,
	}
	esqueletos[model] = dados
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") then adicionarOsso(dados, d) end
	end
	dados.conexao = model.DescendantAdded:Connect(function(d)
		if d:IsA("Motor6D") then adicionarOsso(dados, d) end
	end)
end

local function classificarHumanoid(hum)
	local model = hum.Parent
	if not model or not model:IsA("Model") or esqueletos[model] then return end
	task.delay(0.3, function()
		if not model.Parent or esqueletos[model] then return end
		local jogador = Players:GetPlayerFromCharacter(model)
		if jogador == eu then return end
		if jogador then
			local tipo = ehMonstroJogador(model, jogador, hum) and "monstro" or "player"
			criarEsqueleto(model, tipo, jogador.Name, hum, jogador)
		else
			if MOSTRAR_NPCS and not contem(model.Name, { "dummy", "manequim" }) then
				criarEsqueleto(model, "monstro", model.Name, hum)
			end
		end
	end)
end

local function classificarMotor(motor)
	if not MOSTRAR_NPCS then return end
	local model = motor:FindFirstAncestorOfClass("Model")
	if not model or esqueletos[model] then return end
	if model:FindFirstChildOfClass("Humanoid") then return end
	if not contem(model.Name, PALAVRAS_MONSTRO) then return end
	criarEsqueleto(model, "monstro", model.Name, nil)
end

local function detectarEsqueleto(obj)
	if obj:IsA("Humanoid") then
		classificarHumanoid(obj)
	elseif obj:IsA("Motor6D") then
		classificarMotor(obj)
	end
end

local function escanearEsqueleto()
	local n = 0
	for _, obj in ipairs(workspace:GetDescendants()) do
		local c = obj.ClassName
		if c == "Humanoid" or c == "Motor6D" then pcall(detectarEsqueleto, obj) end
		n += 1
		if n % 4000 == 0 then task.wait() end
	end
end

local function esconderEsqueletos()
	for _, dados in pairs(esqueletos) do
		for _, box in pairs(dados.motores) do
			if box.Visible then box.Visible = false end
		end
		if dados.gui and dados.gui.Enabled then dados.gui.Enabled = false end
	end
end

local function atualizarEsqueletos()
	-- ESP geral desligado: esconde tudo uma vez e não gasta mais nada
	if not ESP_PLAYERS_ON then
		if not escondidoTudo then
			escondidoTudo = true
			esconderEsqueletos()
		end
		return
	end
	escondidoTudo = false

	local camera = workspace.CurrentCamera
	local camPos = camera and camera.CFrame.Position
	local agora = os.clock()
	for model, dados in pairs(esqueletos) do
		if not model:IsDescendantOf(workspace) then
			destruirEsqueleto(model)
		else
			-- reavalia a cada 1s se o jogador virou monstro (ou deixou de ser)
			if dados.jogador and agora - (dados.ultimo or 0) > 1 then
				dados.ultimo = agora
				local novo = ehMonstroJogador(model, dados.jogador, dados.humanoid) and "monstro" or "player"
				if novo ~= dados.tipo then definirTipo(dados, novo) end
			end
			local ativo = (dados.tipo == "player" and SKEL_PLAYERS) or (dados.tipo == "monstro" and SKEL_MONSTROS)
			if dados.humanoid and dados.humanoid.Health <= 0 then ativo = false end
			if ativo and SKEL_DIST > 0 and camPos then
				local raiz = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
				if raiz and (camPos - raiz.Position).Magnitude > SKEL_DIST then ativo = false end
			end

			local mostrarOssos = ativo and ESP_SKEL
			for motor, box in pairs(dados.motores) do
				if mostrarOssos then
					local p0, p1 = motor.Part0, motor.Part1
					local desenhar = false
					if p0 and p1 and p0:IsDescendantOf(workspace) and p1:IsDescendantOf(workspace) then
						local d = p0.CFrame:PointToObjectSpace(p1.Position)
						local mag = d.Magnitude
						if mag > 0.05 then
							box.Adornee = p0
							box.Size = Vector3.new(ESPESSURA, ESPESSURA, mag)
							box.CFrame = CFrame.lookAt(d / 2, d)
							desenhar = true
						end
					end
					if box.Visible ~= desenhar then box.Visible = desenhar end
				elseif box.Visible then
					box.Visible = false
				end
			end

			local mostrarNome = ativo and ESP_NOME
			if mostrarNome and not dados.gui then criarLabel(dados, model) end
			local g = dados.gui
			if g then
				if g.Enabled ~= mostrarNome then g.Enabled = mostrarNome end
				-- texto atualizado ~8x por segundo (não a cada quadro)
				if mostrarNome and camPos and dados.alvo and agora - (dados.ultimoTxt or 0) > 0.12 then
					dados.ultimoTxt = agora
					local dist = (camPos - dados.alvo.Position).Magnitude
					local prefixo = (dados.tipo == "monstro") and "[MONSTRO] " or ""
					local timeTxt = (dados.jogador and dados.jogador.Team) and (" · " .. dados.jogador.Team.Name) or ""
					dados.txt.Text = prefixo .. dados.nome .. " [" .. math.floor(dist) .. "m]" .. timeTxt
				end
			end
		end
	end
end

local avisouErro = false
local conexaoSkel
local contadorQuadro = 0
conexaoSkel = RunService.RenderStepped:Connect(function()
	if shared.ESP_SESSAO ~= SESSAO then conexaoSkel:Disconnect() return end
	contadorQuadro += 1
	if (OTIMIZAR or fpsBaixo) and contadorQuadro % 2 == 1 then return end
	local ok, err = pcall(atualizarEsqueletos)
	if not ok and not avisouErro then
		avisouErro = true
		warn("[ESP Esqueleto] " .. tostring(err))
	end
end)

----------------------------------------------------------------
-- GUI
----------------------------------------------------------------
local jogador = Players.LocalPlayer
local playerGui = jogador:WaitForChild("PlayerGui")

local velha = playerGui:FindFirstChild("ESPControle")
if velha then velha:Destroy() end

local tela = Instance.new("ScreenGui")
tela.Name = "ESPControle"
tela.ResetOnSpawn = false
tela.IgnoreGuiInset = true
tela.DisplayOrder = 999999
tela.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
tela.Parent = playerGui

local quadro = Instance.new("Frame")
quadro.Size = UDim2.fromOffset(150, 240)
quadro.Position = UDim2.new(0, 20, 0.5, 0)
quadro.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
quadro.BorderSizePixel = 0
quadro.ZIndex = 10
quadro.Parent = tela
Instance.new("UICorner", quadro).CornerRadius = UDim.new(0, 10)

local barra = Instance.new("TextLabel")
barra.Size = UDim2.new(1, 0, 0, 22)
barra.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
barra.BorderSizePixel = 0
barra.Text = "≡  arraste aqui"
barra.TextColor3 = Color3.fromRGB(200, 200, 200)
barra.Font = Enum.Font.Gotham
barra.TextSize = 12
barra.Active = true
barra.ZIndex = 11
barra.Parent = quadro
Instance.new("UICorner", barra).CornerRadius = UDim.new(0, 10)

local botao = Instance.new("TextButton")
botao.Size = UDim2.new(1, -12, 0, 38)
botao.Position = UDim2.fromOffset(6, 26)
botao.BorderSizePixel = 0
botao.Font = Enum.Font.GothamBold
botao.TextSize = 16
botao.TextColor3 = Color3.new(1, 1, 1)
botao.ZIndex = 12
botao.Parent = quadro
Instance.new("UICorner", botao).CornerRadius = UDim.new(0, 8)

-- Botões de filtro por raridade
local botoesRaridade = {}
local function atualizarFiltro(r)
	local b = botoesRaridade[r.id]
	if ativos[r.id] then
		b.BackgroundColor3 = r.cor
		b.TextColor3 = Color3.new(0, 0, 0)
	else
		b.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
		b.TextColor3 = Color3.fromRGB(120, 120, 120)
	end
end

for i, r in ipairs(RARIDADES) do
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(24, 28)
	b.Position = UDim2.fromOffset(6 + (i - 1) * 28, 70)
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.TextSize = 14
	b.Text = r.sigla
	b.ZIndex = 12
	b.Parent = quadro
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
	botoesRaridade[r.id] = b
	atualizarFiltro(r)

	b.Activated:Connect(function()
		ativos[r.id] = not ativos[r.id]
		atualizarFiltro(r)
		reescanear()
	end)
end

-- Botões do Esqueleto (Players / Monstro)
local function criarToggleSkel(posX, rotulo, cor, getEstado, setEstado)
	local b = Instance.new("TextButton")
	b.Size = UDim2.fromOffset(66, 28)
	b.Position = UDim2.fromOffset(posX, 138)
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.TextSize = 10
	b.ZIndex = 12
	b.Parent = quadro
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
	local function atualizar()
		if getEstado() then
			b.Text = rotulo .. " ON"
			b.BackgroundColor3 = cor
			b.TextColor3 = Color3.new(0, 0, 0)
		else
			b.Text = rotulo .. " OFF"
			b.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
			b.TextColor3 = Color3.fromRGB(150, 150, 150)
		end
	end
	atualizar()
	b.Activated:Connect(function()
		setEstado(not getEstado())
		atualizar()
	end)
end

criarToggleSkel(6, "Players", COR_PLAYER,
	function() return SKEL_PLAYERS end, function(v) SKEL_PLAYERS = v end)
criarToggleSkel(78, "Monstro", COR_MONSTRO,
	function() return SKEL_MONSTROS end, function(v) SKEL_MONSTROS = v end)

-- Seletor de monstro (lista de jogadores)
local botaoSel = Instance.new("TextButton")
botaoSel.Size = UDim2.new(1, -12, 0, 28)
botaoSel.Position = UDim2.fromOffset(6, 172)
botaoSel.BackgroundColor3 = Color3.fromRGB(130, 35, 35)
botaoSel.BorderSizePixel = 0
botaoSel.Text = "Escolher monstro"
botaoSel.Font = Enum.Font.GothamBold
botaoSel.TextSize = 13
botaoSel.TextColor3 = Color3.new(1, 1, 1)
botaoSel.ZIndex = 12
botaoSel.Parent = quadro
Instance.new("UICorner", botaoSel).CornerRadius = UDim.new(0, 8)

local popup = Instance.new("Frame")
popup.Size = UDim2.fromOffset(200, 230)
popup.Position = UDim2.fromOffset(156, 0)
popup.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
popup.BorderSizePixel = 0
popup.Visible = false
popup.ZIndex = 14
popup.Parent = quadro
Instance.new("UICorner", popup).CornerRadius = UDim.new(0, 10)

local botaoAuto = Instance.new("TextButton")
botaoAuto.Size = UDim2.new(1, -12, 0, 28)
botaoAuto.Position = UDim2.fromOffset(6, 6)
botaoAuto.BorderSizePixel = 0
botaoAuto.Font = Enum.Font.GothamBold
botaoAuto.TextSize = 12
botaoAuto.ZIndex = 15
botaoAuto.Parent = popup
Instance.new("UICorner", botaoAuto).CornerRadius = UDim.new(0, 8)

local function atualizarAutoBtn()
	if AUTO_DETECTAR then
		botaoAuto.Text = "Auto-detectar: ON"
		botaoAuto.BackgroundColor3 = Color3.fromRGB(40, 160, 70)
		botaoAuto.TextColor3 = Color3.new(1, 1, 1)
	else
		botaoAuto.Text = "Auto-detectar: OFF"
		botaoAuto.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
		botaoAuto.TextColor3 = Color3.fromRGB(170, 170, 170)
	end
end
atualizarAutoBtn()
botaoAuto.Activated:Connect(function()
	AUTO_DETECTAR = not AUTO_DETECTAR
	atualizarAutoBtn()
end)

local listaJog = Instance.new("ScrollingFrame")
listaJog.Size = UDim2.new(1, -12, 1, -44)
listaJog.Position = UDim2.fromOffset(6, 38)
listaJog.BackgroundTransparency = 1
listaJog.BorderSizePixel = 0
listaJog.ScrollBarThickness = 4
listaJog.CanvasSize = UDim2.new()
listaJog.AutomaticCanvasSize = Enum.AutomaticSize.Y
listaJog.ZIndex = 15
listaJog.Parent = popup
local layoutJog = Instance.new("UIListLayout", listaJog)
layoutJog.Padding = UDim.new(0, 4)

local function montarLista()
	for _, c in ipairs(listaJog:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
	for _, j in ipairs(Players:GetPlayers()) do
		if j ~= Players.LocalPlayer then
			local b = Instance.new("TextButton")
			b.Size = UDim2.new(1, -6, 0, 32)
			b.BorderSizePixel = 0
			b.Font = Enum.Font.Gotham
			b.TextSize = 12
			b.TextTruncate = Enum.TextTruncate.AtEnd
			b.ZIndex = 16
			b.Parent = listaJog
			Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)

			local function pintar()
				local marcado = MONSTROS_MANUAL[j.Name]
				b.BackgroundColor3 = marcado and COR_MONSTRO or Color3.fromRGB(50, 50, 50)
				b.TextColor3 = marcado and Color3.new(1, 1, 1) or Color3.fromRGB(220, 220, 220)
				b.Text = (marcado and "[MONSTRO] " or "") .. j.DisplayName .. " · " .. j.Name
			end
			pintar()
			b.Activated:Connect(function()
				MONSTROS_MANUAL[j.Name] = (not MONSTROS_MANUAL[j.Name]) or nil
				pintar()
			end)
		end
	end
end

botaoSel.Activated:Connect(function()
	popup.Visible = not popup.Visible
	if popup.Visible then montarLista() end
end)
Players.PlayerAdded:Connect(function()
	if popup.Visible then task.defer(montarLista) end
end)
Players.PlayerRemoving:Connect(function()
	if popup.Visible then task.defer(montarLista) end
end)

-- Botão Instant PP
local botaoPP = Instance.new("TextButton")
botaoPP.Size = UDim2.new(1, -12, 0, 28)
botaoPP.Position = UDim2.fromOffset(6, 104)
botaoPP.BorderSizePixel = 0
botaoPP.Font = Enum.Font.GothamBold
botaoPP.TextSize = 13
botaoPP.TextColor3 = Color3.new(1, 1, 1)
botaoPP.ZIndex = 12
botaoPP.Parent = quadro
Instance.new("UICorner", botaoPP).CornerRadius = UDim.new(0, 8)

local function atualizarPP()
	if INSTANT_PP then
		botaoPP.Text = "Instant PP: ON"
		botaoPP.BackgroundColor3 = Color3.fromRGB(40, 160, 70)
	else
		botaoPP.Text = "Instant PP: OFF"
		botaoPP.BackgroundColor3 = Color3.fromRGB(170, 50, 50)
	end
end
atualizarPP()

botaoPP.Activated:Connect(function()
	INSTANT_PP = not INSTANT_PP
	if INSTANT_PP then
		escanearInstant()
	else
		restaurarInstant()
	end
	atualizarPP()
end)

atualizarBotao = function()
	if ESP_LIGADO then
		botao.Text = "ESP: ON (" .. contador .. ")"
		botao.BackgroundColor3 = Color3.fromRGB(40, 160, 70)
	else
		botao.Text = "ESP: OFF"
		botao.BackgroundColor3 = Color3.fromRGB(170, 50, 50)
	end
end

local trava = false
botao.Activated:Connect(function()
	if trava then return end
	trava = true
	alternar()
	task.delay(0.25, function() trava = false end)
end)

-- Abrir / fechar o painel
local fechar = Instance.new("TextButton")
fechar.Size = UDim2.fromOffset(22, 22)
fechar.Position = UDim2.new(1, -22, 0, 0)
fechar.BackgroundColor3 = Color3.fromRGB(170, 50, 50)
fechar.BorderSizePixel = 0
fechar.Text = "X"
fechar.TextColor3 = Color3.new(1, 1, 1)
fechar.Font = Enum.Font.GothamBold
fechar.TextSize = 12
fechar.ZIndex = 13
fechar.Parent = barra
Instance.new("UICorner", fechar).CornerRadius = UDim.new(0, 8)

local abrir = Instance.new("TextButton")
abrir.Size = UDim2.fromOffset(44, 44)
abrir.Position = quadro.Position
abrir.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
abrir.BorderSizePixel = 0
abrir.Text = "ESP"
abrir.TextColor3 = Color3.fromRGB(255, 220, 0)
abrir.Font = Enum.Font.GothamBold
abrir.TextSize = 14
abrir.Visible = false
abrir.ZIndex = 10
abrir.Parent = tela
Instance.new("UICorner", abrir).CornerRadius = UDim.new(1, 0)

local function mostrarPainel(aberto)
	if aberto then
		quadro.Position = abrir.Position
	else
		abrir.Position = quadro.Position
	end
	quadro.Visible = aberto
	abrir.Visible = not aberto
end

fechar.Activated:Connect(function() mostrarPainel(false) end)
abrir.Activated:Connect(function() mostrarPainel(true) end)

-- Arrastar pela barra
local arrastando, inicioToque, inicioPos
barra.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		arrastando = true
		inicioToque = input.Position
		inicioPos = quadro.Position
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then arrastando = false end
		end)
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if arrastando and (input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch) then
		local d = input.Position - inicioToque
		quadro.Position = UDim2.new(
			inicioPos.X.Scale, inicioPos.X.Offset + d.X,
			inicioPos.Y.Scale, inicioPos.Y.Offset + d.Y
		)
	end
end)

UserInputService.InputBegan:Connect(function(input, processado)
	if processado then return end
	if input.KeyCode == Enum.KeyCode.RightControl then
		mostrarPainel(not quadro.Visible)
	elseif input.KeyCode == Enum.KeyCode.RightShift then
		alternar()
	end
end)

----------------------------------------------------------------
-- MAIS OPÇÕES (cada parte roda protegida: se uma falhar, o resto continua)
----------------------------------------------------------------
local function iniciarMaisOpcoes()
	local TweenService = game:GetService("TweenService")
	local PathfindingService = game:GetService("PathfindingService")
	local Lighting = game:GetService("Lighting")
	local VirtualUser = game:GetService("VirtualUser")

	local OPC = {
		labels = true, distancia = 0,
		chams = true,
		fullbright = false,
		fovLigado = false, fov = 90,
		removerVents = false, ventESP = false,
		saidaESP = false, tracers = false,
		antiAfk = false,
		minRar = 1,
		autoLoot = false, modo = "Teleport", velocidade = 40, tpDelay = 3,
		pausarMonstro = false, distPausa = 50,
		pausaDistancia = false, pesoMax = 10,
		precisaScan = false, reaplicar = false,
	}

	local function sessaoViva() return shared.ESP_SESSAO == SESSAO end

	local function seguro(f, ...)
		local ok, e = pcall(f, ...)
		if not ok then warn("[ESP] " .. tostring(e)) end
	end

	local function parteDe(obj)
		if obj:IsA("BasePart") then return obj end
		if obj:IsA("Model") then
			return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
		end
		return nil
	end

	local function partesTodas(obj)
		if obj:IsA("BasePart") then return { obj } end
		local l = {}
		for _, d in ipairs(obj:GetDescendants()) do
			if d:IsA("BasePart") then table.insert(l, d) end
		end
		return l
	end

	------------------------------------------------------------
	-- Loot Labels + distância máxima dos itens
	------------------------------------------------------------
	local ultLabels, ultDist, ultCount = nil, nil, -1
	local function passoDistancia()
		local cam = workspace.CurrentCamera
		if not cam then return end
		-- sem limite de distância e nada mudou: não precisa percorrer a lista
		if OPC.distancia == 0 and ultDist == 0 and ultLabels == OPC.labels and ultCount == #elementos then return end
		local camPos = cam.CFrame.Position
		for i = #elementos, 1, -1 do
			local e = elementos[i]
			if not e.Parent then
				table.remove(elementos, i)
			else
				local parte = e.Adornee
				local dentro = true
				if OPC.distancia > 0 and parte then
					dentro = (camPos - parte.Position).Magnitude <= OPC.distancia
				end
				if e:IsA("BillboardGui") then
					local alvo = dentro and OPC.labels
					if e.Enabled ~= alvo then e.Enabled = alvo end
				else
					if e.Visible ~= dentro then e.Visible = dentro end
				end
			end
		end
		ultLabels, ultDist, ultCount = OPC.labels, OPC.distancia, #elementos
	end
	task.spawn(function()
		while sessaoViva() do
			task.wait(OPC.otimizar and 0.6 or 0.2)
			seguro(passoDistancia)
		end
	end)

	------------------------------------------------------------
	-- Player Chams (verde = jogadores, vermelho = monstro)
	------------------------------------------------------------
	local chamsLigados = false
	local function passoChams()
		if not (ESP_PLAYERS_ON and OPC.chams) then
			if chamsLigados then
				chamsLigados = false
				for _, dados in pairs(esqueletos) do
					if dados.hl then dados.hl.Enabled = false end
				end
			end
			return
		end
		chamsLigados = true
		for model, dados in pairs(esqueletos) do
			local vivo = (not dados.humanoid) or dados.humanoid.Health > 0
			local tipoOk = (dados.tipo == "player" and SKEL_PLAYERS) or (dados.tipo == "monstro" and SKEL_MONSTROS)
			if vivo and tipoOk and model.Parent then
				if not dados.hl then
					local hl = Instance.new("Highlight")
					hl.Adornee = model
					hl.FillTransparency = 0.6
					hl.OutlineTransparency = 0
					hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
					hl.Parent = pastaSkel
					dados.hl = hl
				end
				local cor = (dados.tipo == "monstro") and Color3.fromRGB(255, 50, 50) or Color3.fromRGB(60, 255, 90)
				if dados.hl.FillColor ~= cor then
					dados.hl.FillColor = cor
					dados.hl.OutlineColor = cor
				end
				if not dados.hl.Enabled then dados.hl.Enabled = true end
			elseif dados.hl and dados.hl.Enabled then
				dados.hl.Enabled = false
			end
		end
	end
	task.spawn(function()
		while sessaoViva() do
			task.wait(OPC.otimizar and 0.7 or 0.25)
			seguro(passoChams)
		end
	end)

	------------------------------------------------------------
	-- Fullbright
	------------------------------------------------------------
	local luzOriginal = nil
	local atmos = {}
	local function luz(ligar)
		if ligar then
			if not luzOriginal then
				luzOriginal = {
					Brightness = Lighting.Brightness,
					ClockTime = Lighting.ClockTime,
					FogEnd = Lighting.FogEnd,
					FogStart = Lighting.FogStart,
					GlobalShadows = Lighting.GlobalShadows,
					Ambient = Lighting.Ambient,
					OutdoorAmbient = Lighting.OutdoorAmbient,
					ExposureCompensation = Lighting.ExposureCompensation,
				}
			end
			Lighting.Brightness = 2
			Lighting.ClockTime = 14
			Lighting.FogStart = 0
			Lighting.FogEnd = 1e6
			Lighting.GlobalShadows = false
			Lighting.Ambient = Color3.fromRGB(190, 190, 190)
			Lighting.OutdoorAmbient = Color3.fromRGB(190, 190, 190)
			Lighting.ExposureCompensation = 0.5
			for _, c in ipairs(Lighting:GetChildren()) do
				if c:IsA("Atmosphere") then
					if atmos[c] == nil then atmos[c] = c.Density end
					c.Density = 0
				end
			end
		elseif luzOriginal then
			for k, v in pairs(luzOriginal) do Lighting[k] = v end
			for c, d in pairs(atmos) do
				if c.Parent then c.Density = d end
			end
			luzOriginal = nil
			atmos = {}
		end
	end

	------------------------------------------------------------
	-- Custom FOV
	------------------------------------------------------------
	local conexaoFov
	conexaoFov = RunService.RenderStepped:Connect(function()
		if not sessaoViva() then conexaoFov:Disconnect() return end
		if OPC.fovLigado then
			local cam = workspace.CurrentCamera
			if cam then cam.FieldOfView = OPC.fov end
		end
	end)

	------------------------------------------------------------
	-- Anti AFK
	------------------------------------------------------------
	eu.Idled:Connect(function()
		if OPC.antiAfk and sessaoViva() then
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.new())
		end
	end)

	------------------------------------------------------------
	-- Vents e Saídas (Remove Vents, Vent ESP, Exit Door ESP, Exit Tracers)
	-- Procura objetos chamados "Vent Entrance" e portas de saída (nome com exit/saída)
	------------------------------------------------------------
	local listaVents, listaSaidas = {}, {}
	local ventOrig = {}
	local caixasVent, caixasSaida, tracers = {}, {}, {}

	local function reescanearAlvos()
		local candVents, candSaidas, todos = {}, {}, {}
		local n = 0
		for _, d in ipairs(workspace:GetDescendants()) do
			n += 1
			if n % 3000 == 0 then task.wait() end
			if d:IsA("BasePart") or d:IsA("Model") then
				local nome = string.lower(d.Name)
				if string.find(nome, "vent entrance", 1, true) or string.find(nome, "vententrance", 1, true) then
					table.insert(candVents, d)
					todos[d] = true
				elseif string.find(nome, "exit", 1, true) or string.find(nome, "saida", 1, true) or string.find(nome, "saída", 1, true) then
					local tam = tamanhoDe(d)
					if tam and maiorLado(tam) >= 4 then
						table.insert(candSaidas, d)
						todos[d] = true
					end
				end
			end
		end
		local function semAncestral(obj)
			local p = obj.Parent
			while p and p ~= workspace do
				if todos[p] then return false end
				p = p.Parent
			end
			return true
		end
		local vents, saidas = {}, {}
		for _, o in ipairs(candVents) do if semAncestral(o) then table.insert(vents, o) end end
		for _, o in ipairs(candSaidas) do if semAncestral(o) then table.insert(saidas, o) end end
		listaVents, listaSaidas = vents, saidas
		OPC.reaplicar = true
	end

	local function aplicarVents(ligar)
		if ligar then
			for _, v in ipairs(listaVents) do
				for _, p in ipairs(partesTodas(v)) do
					if ventOrig[p] == nil then ventOrig[p] = { p.Transparency, p.CanCollide } end
					p.Transparency = 1
					p.CanCollide = false
				end
			end
		else
			for p, o in pairs(ventOrig) do
				if p.Parent then
					p.Transparency = o[1]
					p.CanCollide = o[2]
				end
				ventOrig[p] = nil
			end
		end
	end

	local function sincronizarCaixas(mapa, lista, cor, ligado)
		local naLista = {}
		for _, o in ipairs(lista) do naLista[o] = true end
		for o, boxes in pairs(mapa) do
			if (not ligado) or (not naLista[o]) or (not o.Parent) then
				for _, b in ipairs(boxes) do b:Destroy() end
				mapa[o] = nil
			end
		end
		if not ligado then return end
		for _, o in ipairs(lista) do
			if not mapa[o] and o.Parent then
				local boxes = {}
				local partes = partesTodas(o)
				for i = 1, math.min(#partes, 12) do
					local p = partes[i]
					local b = Instance.new("BoxHandleAdornment")
					b.Adornee = p
					b.Size = p.Size
					b.Color3 = cor
					b.Transparency = 0.5
					b.AlwaysOnTop = true
					b.ZIndex = 1
					b.Parent = pastaSkel
					table.insert(boxes, b)
				end
				mapa[o] = boxes
			end
		end
	end

	local function sincronizarTracers()
		local naLista = {}
		for _, o in ipairs(listaSaidas) do naLista[o] = true end
		for o, box in pairs(tracers) do
			if (not OPC.tracers) or (not naLista[o]) or (not o.Parent) then
				box:Destroy()
				tracers[o] = nil
			end
		end
		if not OPC.tracers then return end
		for _, o in ipairs(listaSaidas) do
			if not tracers[o] and o.Parent then
				local b = Instance.new("BoxHandleAdornment")
				b.AlwaysOnTop = true
				b.ZIndex = 1
				b.Transparency = 0.2
				b.Color3 = Color3.fromRGB(0, 255, 120)
				b.Size = Vector3.new(0.08, 0.08, 1)
				b.Visible = false
				b.Parent = pastaSkel
				tracers[o] = b
			end
		end
	end

	local conexaoTracer
	conexaoTracer = RunService.RenderStepped:Connect(function()
		if not sessaoViva() then conexaoTracer:Disconnect() return end
		if next(tracers) == nil then return end
		local char = eu.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		for o, box in pairs(tracers) do
			local alvo = o.Parent and parteDe(o)
			if hrp and alvo then
				local d = hrp.CFrame:PointToObjectSpace(alvo.Position)
				local mag = d.Magnitude
				if mag > 1 then
					box.Adornee = hrp
					box.Size = Vector3.new(0.08, 0.08, mag)
					box.CFrame = CFrame.lookAt(d / 2, d)
					box.Visible = true
				else
					box.Visible = false
				end
			else
				box.Visible = false
			end
		end
	end)

	task.spawn(function()
		local ultimo = 0
		while sessaoViva() do
			task.wait(0.5)
			local alguma = OPC.removerVents or OPC.ventESP or OPC.saidaESP or OPC.tracers
			if alguma and (OPC.precisaScan or os.clock() - ultimo > 8) then
				OPC.precisaScan = false
				ultimo = os.clock()
				seguro(reescanearAlvos)
			end
			if OPC.reaplicar then
				OPC.reaplicar = false
				seguro(aplicarVents, OPC.removerVents)
			end
			if alguma or next(caixasVent) or next(caixasSaida) or next(tracers) then
				seguro(sincronizarCaixas, caixasVent, listaVents, Color3.fromRGB(255, 140, 0), OPC.ventESP)
				seguro(sincronizarCaixas, caixasSaida, listaSaidas, Color3.fromRGB(0, 255, 120), OPC.saidaESP)
				seguro(sincronizarTracers)
			end
			if OPC.fullbright then seguro(luz, true) end
		end
	end)

	------------------------------------------------------------
	-- Auto Loot (anda até os itens marcados no ESP e coleta)
	------------------------------------------------------------
	local tentados = {}

	local function promptDe(obj)
		if obj:IsA("ProximityPrompt") then return obj end
		return obj:FindFirstChildWhichIsA("ProximityPrompt", true)
	end

	local function monstroPerto(hrp)
		for model, dados in pairs(esqueletos) do
			if dados.tipo == "monstro" then
				local r = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
				if r and (r.Position - hrp.Position).Magnitude <= OPC.distPausa then return true end
			end
		end
		return false
	end

	local function detectorDe(obj)
		if obj:IsA("ClickDetector") then return obj end
		return obj:FindFirstChildWhichIsA("ClickDetector", true)
	end

	local coletados = 0

	local function disponivel(obj)
		if not obj.Parent then return nil end
		if tentados[obj] and os.clock() - tentados[obj] <= 20 then return nil end
		local prompt = promptDe(obj)
		local detector = detectorDe(obj)
		if not ((prompt and prompt.Enabled) or detector) then return nil end
		local parte = parteDe(obj)
		if not parte then return nil end
		local peso = pesoDe(obj)
		if peso and peso > OPC.pesoMax then return nil end
		return prompt, detector, parte
	end

	local function contarAlvos()
		local n = 0
		for obj in pairs(marcados) do
			if disponivel(obj) ~= nil or (obj.Parent and detectorDe(obj) and not (tentados[obj] and os.clock() - tentados[obj] <= 20)) then
				n += 1
			end
		end
		return n
	end

	local function escolherAlvo(hrp)
		local melhor, melhorD, melhorPrompt, melhorDet
		for obj in pairs(marcados) do
			local prompt, detector, parte = disponivel(obj)
			if parte then
				local d = (parte.Position - hrp.Position).Magnitude
				if not melhorD or d < melhorD then
					melhor, melhorD, melhorPrompt, melhorDet = obj, d, prompt, detector
				end
			end
		end
		return melhor, melhorPrompt, melhorDet
	end

	-- Coleta usando todos os métodos disponíveis (prompt, clique e toque)
	local function coletar(prompt, detector, hrp, parte)
		if prompt then
			pcall(function()
				prompt.HoldDuration = 0
				prompt.RequiresLineOfSight = false
				if prompt.MaxActivationDistance < 20 then prompt.MaxActivationDistance = 20 end
			end)
			if type(fireproximityprompt) == "function" then
				pcall(fireproximityprompt, prompt)
			end
			pcall(function()
				prompt:InputHoldBegin()
				task.wait(0.1)
				prompt:InputHoldEnd()
			end)
		end
		if detector and type(fireclickdetector) == "function" then
			pcall(fireclickdetector, detector)
		end
		if parte and hrp and type(firetouchinterest) == "function" then
			pcall(function()
				firetouchinterest(hrp, parte, 0)
				task.wait()
				firetouchinterest(hrp, parte, 1)
			end)
		end
	end

	local function irAte(hrp, hum, pos)
		if OPC.modo == "Teleport" then
			hrp.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
			hrp.AssemblyLinearVelocity = Vector3.zero
			task.wait(OPC.tpDelay / 10)
			return true
		end

		if OPC.modo == "Tween" then
			local dist = (pos - hrp.Position).Magnitude
			local tempo = math.max(dist / OPC.velocidade, 0.1)
			local tw = TweenService:Create(hrp, TweenInfo.new(tempo, Enum.EasingStyle.Linear), { CFrame = CFrame.new(pos + Vector3.new(0, 3, 0)) })
			tw:Play()
			while tw.PlaybackState == Enum.PlaybackState.Playing and sessaoViva() and OPC.autoLoot do
				if OPC.pausarMonstro and monstroPerto(hrp) then
					tw:Cancel()
					return false
				end
				task.wait(0.05)
			end
			return true
		end

		local path = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
		local ok = pcall(function() path:ComputeAsync(hrp.Position, pos) end)
		if not ok or path.Status ~= Enum.PathStatus.Success then return false end
		for _, wp in ipairs(path:GetWaypoints()) do
			if not (sessaoViva() and OPC.autoLoot) then return false end
			if OPC.pausarMonstro and monstroPerto(hrp) then return false end
			if wp.Action == Enum.PathWaypointAction.Jump then hum.Jump = true end
			hum:MoveTo(wp.Position)
			local feito = false
			local c = hum.MoveToFinished:Connect(function() feito = true end)
			local t0 = os.clock()
			while not feito and os.clock() - t0 < 3 do task.wait(0.05) end
			c:Disconnect()
			if (pos - hrp.Position).Magnitude <= 6 then break end
		end
		return true
	end

	local viajado = 0
	local function passoAutoLoot()
		if not OPC.autoLoot then return end
		if not ESP_LIGADO then alternar() end -- o farm usa os itens marcados pelo ESP
		local char = eu.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hrp or not hum or hum.Health <= 0 then return end
		if OPC.pausarMonstro and monstroPerto(hrp) then return end

		local obj, prompt, detector = escolherAlvo(hrp)
		if not obj then return end
		tentados[obj] = os.clock()
		local parte = parteDe(obj)
		if not parte then return end
		viajado += (parte.Position - hrp.Position).Magnitude

		for tentativa = 1, 3 do
			if not (sessaoViva() and OPC.autoLoot) then return end
			if not irAte(hrp, hum, parte.Position) then break end
			coletar(prompt, detector, hrp, parte)
			task.wait(0.35)
			local sumiu = (not obj.Parent) or (not obj:IsDescendantOf(workspace)) or (prompt and not prompt.Enabled)
			if sumiu then
				coletados += 1
				break
			end
			parte = parteDe(obj)
			if not parte then break end
		end

		if OPC.pausaDistancia and viajado >= 300 then
			viajado = 0
			task.wait(5)
		end
	end
	task.spawn(function()
		while sessaoViva() do
			task.wait(0.25)
			seguro(passoAutoLoot)
		end
	end)

	------------------------------------------------------------
	-- AUTO PERFECT (basquete): segura o botão USAR até aparecer "PERFEITO" e solta
	------------------------------------------------------------
	local GuiService = game:GetService("GuiService")
	local ContextActionService = game:GetService("ContextActionService")
	local VIM = nil
	pcall(function() VIM = game:GetService("VirtualInputManager") end)
	local pguiTiro = eu:WaitForChild("PlayerGui")

	OPC.autoPerfeito = false
	OPC.autoTiro = false
	OPC.metodoTiro = UserInputService.TouchEnabled and "Touch" or "Mouse"
	OPC.tiroMax = 15     -- décimos de segundo (1.5s)
	OPC.tiroEspera = 10  -- décimos de segundo (1.0s)
	OPC.scanTexto = nil

	-- lista de todos os textos da tela (menos os do próprio menu)
	local listaTextos = {}
	local function registrarTexto(d)
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			if d:FindFirstAncestor("ESPJanela") or d:FindFirstAncestor("ESPControle") or d:FindFirstAncestor("ESPErro") then
				return
			end
			listaTextos[d] = true
		end
	end
	for _, d in ipairs(pguiTiro:GetDescendants()) do registrarTexto(d) end
	pguiTiro.DescendantAdded:Connect(registrarTexto)
	pguiTiro.DescendantRemoving:Connect(function(d) listaTextos[d] = nil end)

	local function guiVisivel(obj)
		local p = obj
		while p and p ~= pguiTiro do
			if p:IsA("GuiObject") and not p.Visible then return false end
			if p:IsA("ScreenGui") and not p.Enabled then return false end
			p = p.Parent
		end
		return p == pguiTiro
	end

	local PALAVRAS_PERFEITO = { "perfeito", "perfect" }
	local function perfeitoAgora()
		for d in pairs(listaTextos) do
			if d.Parent and d.TextTransparency < 0.9 and contem(d.Text, PALAVRAS_PERFEITO) and guiVisivel(d) then
				return true
			end
		end
		return false
	end

	local function acharUsar()
		for d in pairs(listaTextos) do
			if d.Parent and string.upper((string.gsub(d.Text, "%s", ""))) == "USAR" and guiVisivel(d) then
				return d
			end
		end
		return nil
	end

	local function centroDe(d)
		local sg = d:FindFirstAncestorOfClass("ScreenGui")
		local inset = (sg and sg.IgnoreGuiInset) and Vector2.new(0, 0) or GuiService:GetGuiInset()
		return d.AbsolutePosition + inset + d.AbsoluteSize / 2
	end

	local pressionando = false
	local posPress = nil
	local sinalBtn = nil
	OPC.statusTiro = "Auto Shoot ainda não rodou."

	-- sobe da etiqueta "USAR" até o botão de verdade
	local function botaoDe(label)
		local p = label
		while p and p ~= pguiTiro do
			if p:IsA("GuiButton") then return p end
			p = p.Parent
		end
		return nil
	end

	-- dispara as funções que o jogo ligou no botão (precisa de getconnections no executor)
	local function dispararSinais(btn, nomes, entrada)
		if type(getconnections) ~= "function" then return false end
		local feito = false
		for _, nome in ipairs(nomes) do
			local okS, conns = pcall(function() return getconnections(btn[nome]) end)
			if okS and typeof(conns) == "table" then
				for _, c in ipairs(conns) do
					pcall(function()
						if nome == "InputBegan" or nome == "InputEnded" then c:Fire(entrada) else c:Fire() end
					end)
					feito = true
				end
			end
		end
		return feito
	end

	local function entradaFalsa(estado, p)
		return {
			UserInputType = Enum.UserInputType.Touch,
			UserInputState = estado,
			Position = Vector3.new(p.X, p.Y, 0),
			KeyCode = Enum.KeyCode.Unknown,
		}
	end

	local function pressionar()
		pressionando = false
		if OPC.metodoTiro == "Tool" then
			local tool = eu.Character and eu.Character:FindFirstChildOfClass("Tool")
			if tool then
				pcall(function() tool:Activate() end)
				pressionando = true
			end
			return
		end
		if OPC.metodoTiro == "Signal" then
			local lbl = acharUsar()
			local btn = lbl and botaoDe(lbl)
			if not btn then return end
			local p = centroDe(lbl)
			posPress = p
			sinalBtn = btn
			if dispararSinais(btn, { "MouseButton1Down", "InputBegan" }, entradaFalsa(Enum.UserInputState.Begin, p)) then
				pressionando = true
			end
			return
		end
		local btn = acharUsar()
		if not (btn and VIM) then return end
		local p = centroDe(btn)
		posPress = p
		pcall(function()
			if OPC.metodoTiro == "Touch" then
				VIM:SendTouchEvent(7, 0, p.X, p.Y)
			else
				VIM:SendMouseButtonEvent(p.X, p.Y, 0, true, game, 1)
			end
		end)
		pressionando = true
	end

	local function soltar()
		local tool = eu.Character and eu.Character:FindFirstChildOfClass("Tool")
		if OPC.metodoTiro == "Tool" then
			if tool then pcall(function() tool:Deactivate() end) end
		elseif OPC.metodoTiro == "Signal" then
			local p = posPress or Vector2.new(0, 0)
			if sinalBtn then
				dispararSinais(sinalBtn, { "MouseButton1Up", "InputEnded" }, entradaFalsa(Enum.UserInputState.End, p))
			end
			sinalBtn = nil
		else
			local p = posPress
			if not p then
				local btn = acharUsar()
				p = btn and centroDe(btn)
			end
			if p and VIM then
				pcall(function()
					if OPC.metodoTiro == "Touch" then
						VIM:SendTouchEvent(7, 2, p.X, p.Y)
					else
						VIM:SendMouseButtonEvent(p.X, p.Y, 0, false, game, 1)
					end
				end)
			end
			if tool then pcall(function() tool:Deactivate() end) end
		end
		pressionando = false
		posPress = nil
	end

	-- Auto Shoot: segura sozinho e solta no PERFEITO
	local function passoTiro()
		if not OPC.autoTiro then return end
		local t0 = os.clock()
		while perfeitoAgora() and os.clock() - t0 < 1.5 do task.wait(0.05) end
		local usaTexto = not perfeitoAgora() -- se o aviso fica fixo na tela, só vale o tempo máximo

		pressionar()
		if not pressionando then
			OPC.statusTiro = "FALHOU ao apertar (" .. OPC.metodoTiro .. "). Botão USAR: "
				.. (acharUsar() and "achado" or "NÃO achado")
				.. " | VIM: " .. (VIM and "sim" or "não")
				.. " | getconnections: " .. ((type(getconnections) == "function") and "sim" or "não")
				.. ". Tente outro Press method."
			task.wait(0.5)
			return
		end
		local t1 = os.clock()
		local limite = OPC.tiroMax / 10
		local visto = nil
		while OPC.autoTiro and sessaoViva() and os.clock() - t1 < limite do
			if usaTexto and perfeitoAgora() then
				visto = os.clock() - t1
				break
			end
			task.wait(0.02)
		end
		soltar()
		if visto then
			OPC.statusTiro = string.format("Apertou (%s) e soltou: PERFEITO apareceu em %.2fs.", OPC.metodoTiro, visto)
		elseif usaTexto then
			OPC.statusTiro = string.format("Apertou (%s), mas PERFEITO NÃO apareceu em %.1fs; soltou pelo tempo. Ajuste 'Max hold time' ou veja o Scan.", OPC.metodoTiro, limite)
		else
			OPC.statusTiro = string.format("Apertou (%s). O aviso PERFEITO fica fixo na tela, então soltou pelo tempo (%.1fs).", OPC.metodoTiro, limite)
		end
		task.wait(OPC.tiroEspera / 10)
	end
	task.spawn(function()
		while sessaoViva() do
			task.wait(OPC.autoTiro and 0.1 or 0.4)
			seguro(passoTiro)
		end
	end)

	-- Auto Release: você segura, o script solta quando aparece PERFEITO
	local ultimoSolto = 0
	local function passoPerfeito()
		if not OPC.autoPerfeito or OPC.autoTiro then return end
		if os.clock() - ultimoSolto < 1.2 then return end
		if perfeitoAgora() then
			ultimoSolto = os.clock()
			soltar()
		end
	end
	task.spawn(function()
		while sessaoViva() do
			task.wait(OPC.autoPerfeito and 0.03 or 0.3)
			seguro(passoPerfeito)
		end
	end)

	-- Diagnóstico: mostra o que o script enxerga do arremesso
	local function caminhoCurto(d)
		return (d:GetFullName():gsub("^.-PlayerGui%.", ""))
	end
	local function escanearTiro()
		local t = {}
		local usar = acharUsar()
		table.insert(t, "USAR: " .. (usar and caminhoCurto(usar) or "NOT FOUND"))
		table.insert(t, "VIM: " .. (VIM and "yes" or "no") .. " | touch: " .. tostring(UserInputService.TouchEnabled))
		local tool = eu.Character and eu.Character:FindFirstChildOfClass("Tool")
		table.insert(t, "Tool: " .. (tool and tool.Name or "none"))
		local n = 0
		local pal = { "perfeito", "perfect", "bom", "good", "ruim", "bad", "miss", "excelente", "great", "early", "late" }
		for d in pairs(listaTextos) do
			if d.Parent and guiVisivel(d) and contem(d.Text, pal) then
				n += 1
				if n <= 6 then table.insert(t, caminhoCurto(d) .. " = " .. d.Text) end
			end
		end
		local acoes = {}
		pcall(function()
			for nome in pairs(ContextActionService:GetAllBoundActionInfo()) do table.insert(acoes, nome) end
		end)
		table.sort(acoes)
		table.insert(t, "Actions: " .. table.concat(acoes, ", "))
		return table.concat(t, "\n")
	end

	------------------------------------------------------------
	-- COMBATE: Speed + Auto Attack (perfis separados: player / monstro)
	------------------------------------------------------------
	local PERFIL = {
		player = { speedOn = false, speed = 24, atkOn = false, atkPlayers = false, atkMonstro = true,
			alcance = 8, angulo = 60, espera = 4 },
		monstro = { speedOn = false, speed = 24, atkOn = false, atkPlayers = true, atkMonstro = false,
			alcance = 8, angulo = 60, espera = 4 },
	}
	OPC.papelModo = "Auto"      -- Auto / Player / Monster
	OPC.papelAtual = "player"   -- "player" ou "monstro" (qual perfil está valendo)
	OPC.metodoAtk = "Both"      -- Tool / Click / Both
	OPC.ignorarTime = false
	OPC.statusAtk = "Auto Attack parado."

	local function calcularPapel()
		if OPC.papelModo == "Player" then return "player" end
		if OPC.papelModo == "Monster" then return "monstro" end
		local char = eu.Character
		if not char then return "player" end
		local hum = char:FindFirstChildOfClass("Humanoid")
		return ehMonstroJogador(char, eu, hum) and "monstro" or "player"
	end

	task.spawn(function()
		while sessaoViva() do
			seguro(function() OPC.papelAtual = calcularPapel() end)
			task.wait(0.5)
		end
	end)

	-- Speed: "WalkSpeed" (reaplica sempre que o jogo mudar) ou "CFrame" (anda por cima do jogo)
	OPC.metodoVel = "WalkSpeed"
	OPC.velResets = 0
	local velHum, velOrig, velSinal = nil, nil, nil
	local velFrame = 0

	local function ligarHumanoid(hum)
		if velSinal then velSinal:Disconnect() velSinal = nil end
		velHum, velOrig = hum, nil
		-- se o jogo mudar o WalkSpeed, volta na hora (no máximo 3x por quadro, evita briga infinita)
		velSinal = hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
			local perfil = PERFIL[OPC.papelAtual]
			if sessaoViva() and perfil.speedOn and OPC.metodoVel == "WalkSpeed"
				and hum.WalkSpeed ~= perfil.speed and velFrame < 3 then
				velFrame += 1
				OPC.velResets += 1
				hum.WalkSpeed = perfil.speed
			end
		end)
	end

	local conexaoVel
	conexaoVel = RunService.Heartbeat:Connect(function(dt)
		if not sessaoViva() then
			conexaoVel:Disconnect()
			if velSinal then velSinal:Disconnect() velSinal = nil end
			if velHum and velHum.Parent and velOrig then velHum.WalkSpeed = velOrig end
			return
		end
		velFrame = 0
		local char = eu.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum then return end
		if velHum ~= hum then ligarHumanoid(hum) end
		local perfil = PERFIL[OPC.papelAtual]
		if perfil.speedOn then
			if OPC.metodoVel == "WalkSpeed" then
				if velOrig == nil then velOrig = hum.WalkSpeed end
				if hum.WalkSpeed ~= perfil.speed then hum.WalkSpeed = perfil.speed end
			else
				if velOrig ~= nil then
					hum.WalkSpeed = velOrig
					velOrig = nil
				end
				local hrp = char:FindFirstChild("HumanoidRootPart")
				local dir = hum.MoveDirection
				local extra = perfil.speed - hum.WalkSpeed
				if hrp and dir.Magnitude > 0 and extra > 0 then
					hrp.CFrame = hrp.CFrame + dir.Unit * extra * dt
				end
			end
		elseif velOrig ~= nil then
			hum.WalkSpeed = velOrig
			velOrig = nil
		end
	end)

	-- também aplica ANTES da física (jogos que resetam o speed no RenderStepped/Stepped)
	local conexaoVel2
	conexaoVel2 = RunService.Stepped:Connect(function()
		if not sessaoViva() then conexaoVel2:Disconnect() return end
		local perfil = PERFIL[OPC.papelAtual]
		if perfil.speedOn and OPC.metodoVel == "WalkSpeed" and velHum and velHum.Parent
			and velHum.WalkSpeed ~= perfil.speed then
			velHum.WalkSpeed = perfil.speed
		end
	end)

	local function textoSpeed()
		local perfil = PERFIL[OPC.papelAtual]
		local atual = (velHum and velHum.Parent) and (math.floor(velHum.WalkSpeed * 10) / 10) or "?"
		return "SPEED: " .. (perfil.speedOn and "ON" or "OFF") .. " (" .. OPC.papelAtual .. ")  |  method "
			.. OPC.metodoVel .. "  |  WalkSpeed now: " .. tostring(atual)
			.. "  |  game resets: " .. OPC.velResets
			.. (OPC.velResets > 10 and "  ->  try the CFrame method" or "")
	end

	-- Auto Attack: ataca quando um alvo está dentro do alcance E na frente de você
	local ultimoAtk = 0
	local function passoAtaque()
		local perfil = PERFIL[OPC.papelAtual]
		if not perfil.atkOn then return end
		local char = eu.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local meuHum = char and char:FindFirstChildOfClass("Humanoid")
		if not hrp or not meuHum or meuHum.Health <= 0 then return end
		local agora = os.clock()
		if agora - ultimoAtk < perfil.espera / 10 then return end

		local frente = hrp.CFrame.LookVector
		local cosMin = math.cos(math.rad(perfil.angulo))
		local melhorD, melhorNome = nil, nil
		for model, dados in pairs(esqueletos) do
			local quer = (dados.tipo == "player" and perfil.atkPlayers) or (dados.tipo == "monstro" and perfil.atkMonstro)
			if quer and model.Parent and (not dados.humanoid or dados.humanoid.Health > 0)
				and not (OPC.ignorarTime and dados.jogador and eu.Team and dados.jogador.Team == eu.Team) then
				local raiz = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
				if raiz then
					local delta = raiz.Position - hrp.Position
					local d = delta.Magnitude
					if d <= perfil.alcance and d > 0.05 and frente:Dot(delta / d) >= cosMin then
						if not melhorD or d < melhorD then melhorD, melhorNome = d, dados.nome end
					end
				end
			end
		end

		if not melhorD then
			OPC.statusAtk = "Sem alvo na frente (alcance " .. perfil.alcance .. ", ângulo ±" .. perfil.angulo .. "°)."
			return
		end

		ultimoAtk = agora
		local m = OPC.metodoAtk
		if m == "Tool" or m == "Both" then
			local tool = char:FindFirstChildOfClass("Tool")
			if tool then pcall(function() tool:Activate() end) end
		end
		if m == "Click" or m == "Both" then
			pcall(function()
				local cam = workspace.CurrentCamera
				local centro = cam and (cam.ViewportSize / 2) or Vector2.new()
				VirtualUser:CaptureController()
				VirtualUser:ClickButton1(centro)
			end)
		end
		OPC.statusAtk = string.format("Atacou %s a %.1f studs (%s).", melhorNome, melhorD, m)
	end
	task.spawn(function()
		while sessaoViva() do
			task.wait(PERFIL[OPC.papelAtual].atkOn and 0.05 or 0.3)
			seguro(passoAtaque)
		end
	end)

	------------------------------------------------------------
	-- OTIMIZAÇÃO (FPS Boost, materiais simples, contador de FPS)
	------------------------------------------------------------
	OPC.fpsBoost = false
	OPC.materiaisSimples = false
	OPC.otimizar = false

	local fpsAtual = 60
	do
		local acum, quadros = 0, 0
		local conexaoFps
		conexaoFps = RunService.Heartbeat:Connect(function(dt)
			if not sessaoViva() then conexaoFps:Disconnect() return end
			acum += dt
			quadros += 1
			if acum >= 0.5 then
				fpsAtual = math.floor(quadros / acum + 0.5)
				if fpsAtual < 30 then fpsBaixo = true elseif fpsAtual >= 45 then fpsBaixo = false end
				acum, quadros = 0, 0
			end
		end)
	end

	local CLASSES_EFEITO = { "ParticleEmitter", "Trail", "Beam", "Fire", "Smoke", "Sparkles", "PostEffect" }
	local efeitosOrig = setmetatable({}, { __mode = "k" })
	local qualidadeOrig = nil
	local sombrasOrig = nil

	local function desligarEfeito(obj)
		for _, c in ipairs(CLASSES_EFEITO) do
			if obj:IsA(c) then
				if obj.Enabled then
					efeitosOrig[obj] = true
					obj.Enabled = false
				end
				return
			end
		end
	end

	local function fpsBoost(ligar)
		if ligar then
			if sombrasOrig == nil then sombrasOrig = Lighting.GlobalShadows end
			Lighting.GlobalShadows = false
			pcall(function()
				if not qualidadeOrig then qualidadeOrig = settings().Rendering.QualityLevel end
				settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
			end)
			task.spawn(function()
				for _, d in ipairs(Lighting:GetDescendants()) do desligarEfeito(d) end
				local n = 0
				for _, d in ipairs(workspace:GetDescendants()) do
					n += 1
					if n % 2000 == 0 then task.wait() end
					if not OPC.fpsBoost then return end
					desligarEfeito(d)
				end
			end)
		else
			if sombrasOrig ~= nil then
				Lighting.GlobalShadows = sombrasOrig
				sombrasOrig = nil
			end
			if qualidadeOrig then
				pcall(function() settings().Rendering.QualityLevel = qualidadeOrig end)
				qualidadeOrig = nil
			end
			for obj in pairs(efeitosOrig) do
				if obj.Parent then pcall(function() obj.Enabled = true end) end
				efeitosOrig[obj] = nil
			end
		end
	end

	workspace.DescendantAdded:Connect(function(d)
		if OPC.fpsBoost and sessaoViva() then desligarEfeito(d) end
	end)

	local matOrig = setmetatable({}, { __mode = "k" })
	local function simplificar(ligar)
		if ligar then
			task.spawn(function()
				local n = 0
				for _, d in ipairs(workspace:GetDescendants()) do
					n += 1
					if n % 1500 == 0 then task.wait() end
					if not OPC.materiaisSimples then return end
					if d:IsA("BasePart") and not d:IsA("Terrain") and matOrig[d] == nil then
						matOrig[d] = { d.Material, d.Reflectance, d.CastShadow }
						d.Material = Enum.Material.SmoothPlastic
						d.Reflectance = 0
						d.CastShadow = false
					end
				end
			end)
		else
			for p, o in pairs(matOrig) do
				if p.Parent then
					p.Material = o[1]
					p.Reflectance = o[2]
					p.CastShadow = o[3]
				end
				matOrig[p] = nil
			end
		end
	end

	------------------------------------------------------------
	-- JANELA: visual igual ao menu do print (abas, linhas com switch, sliders)
	------------------------------------------------------------
	local NOME_MENU = "NOVALUA"
	local tema = { acento = Color3.fromRGB(110, 80, 255) }
	local COR_FUNDO = Color3.fromRGB(10, 10, 16)
	local COR_LATERAL = Color3.fromRGB(14, 14, 22)
	local COR_LINHA = Color3.fromRGB(22, 22, 34)
	local COR_TEXTO = Color3.fromRGB(235, 235, 245)
	local COR_SUB = Color3.fromRGB(115, 115, 140)
	local COR_OFF = Color3.fromRGB(58, 58, 74)
	OPC.opacidade = 100


	local pgui = eu:WaitForChild("PlayerGui")
	local velhaJanela = pgui:FindFirstChild("ESPJanela")
	if velhaJanela then velhaJanela:Destroy() end

	local function novo(classe, props, pai)
		local o = Instance.new(classe)
		for k, v in pairs(props) do o[k] = v end
		if pai then o.Parent = pai end
		return o
	end

	local function canto(o, r)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, r)
		c.Parent = o
	end

	local acentos = {}
	local function acento(obj, prop)
		obj[prop] = tema.acento
		table.insert(acentos, { obj, prop })
	end
	local function aplicarTema()
		for _, a in ipairs(acentos) do
			pcall(function() a[1][a[2]] = tema.acento end)
		end
	end

	local gui = novo("ScreenGui", {
		Name = "ESPJanela", ResetOnSpawn = false, IgnoreGuiInset = true,
		DisplayOrder = 999998, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, pgui)

	local janela = novo("Frame", {
		Size = UDim2.fromOffset(540, 360), AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0), BackgroundColor3 = COR_FUNDO,
		BorderSizePixel = 0, Active = true,
	}, gui)
	canto(janela, 6)
	novo("UIStroke", { Thickness = 1, Color = Color3.fromRGB(42, 42, 64), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, janela)
	local escalaUI = novo("UIScale", {}, janela)
	local function ajustarEscala()
		local cam = workspace.CurrentCamera
		if not cam then return end
		local v = cam.ViewportSize
		escalaUI.Scale = math.clamp(math.min((v.X - 24) / 540, (v.Y - 24) / 360), 0.55, 1)
	end
	ajustarEscala()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(ajustarEscala)
	end

	local linhaTopo = novo("Frame", { Size = UDim2.new(1, 0, 0, 2), BorderSizePixel = 0 }, janela)
	acento(linhaTopo, "BackgroundColor3")

	-- Cabeçalho (arraste por aqui)
	local cabecalho = novo("Frame", {
		Size = UDim2.new(1, 0, 0, 56), BackgroundTransparency = 1, Active = true,
	}, janela)
	-- avatar (skin) do jogador que executou
	local avatarUrl = nil
	local avatarDestinos = {}
	local function usarAvatar(img)
		if avatarUrl then img.Image = avatarUrl else table.insert(avatarDestinos, img) end
	end
	task.spawn(function()
		local ok, url = pcall(function()
			return Players:GetUserThumbnailAsync(eu.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		if ok and url then
			avatarUrl = url
			for _, img in ipairs(avatarDestinos) do img.Image = url end
		end
	end)

	local avatar = novo("ImageLabel", {
		Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(14, 8),
		BackgroundColor3 = COR_LINHA, BorderSizePixel = 0, Image = "",
	}, cabecalho)
	canto(avatar, 100)
	local avContorno = novo("UIStroke", { Thickness = 2 }, avatar)
	acento(avContorno, "Color")
	usarAvatar(avatar)

	novo("TextLabel", {
		Size = UDim2.fromOffset(260, 20), Position = UDim2.fromOffset(62, 9),
		BackgroundTransparency = 1, Text = eu.DisplayName, Font = Enum.Font.GothamBlack,
		TextSize = 15, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, cabecalho)
	novo("TextLabel", {
		Size = UDim2.fromOffset(260, 14), Position = UDim2.fromOffset(62, 30),
		BackgroundTransparency = 1, Text = "@" .. eu.Name .. "  ·  " .. NOME_MENU .. "  ·  RIGHT CTRL",
		Font = Enum.Font.Gotham, TextSize = 9, TextColor3 = COR_SUB,
		TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
	}, cabecalho)
	local seloTxt
	local selo = novo("Frame", {
		Size = UDim2.fromOffset(86, 24), AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -14, 0.5, 0), BackgroundColor3 = Color3.fromRGB(16, 34, 32),
		BorderSizePixel = 0,
	}, cabecalho)
	canto(selo, 4)
	seloTxt = novo("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "● ONLINE",
		Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = Color3.fromRGB(90, 230, 170),
	}, selo)

	-- Arrastar a janela
	local arrastandoJanela, inicioJ, posJ = false, nil, nil
	cabecalho.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			arrastandoJanela = true
			inicioJ = input.Position
			posJ = janela.Position
		end
	end)

	-- Barra lateral
	local lateral = novo("Frame", {
		Size = UDim2.new(0, 150, 1, -56), Position = UDim2.fromOffset(0, 56),
		BackgroundColor3 = COR_LATERAL, BorderSizePixel = 0,
	}, janela)
	novo("TextLabel", {
		Size = UDim2.new(1, -16, 0, 20), Position = UDim2.fromOffset(14, 10),
		BackgroundTransparency = 1, Text = "MENU", Font = Enum.Font.GothamBold,
		TextSize = 10, TextColor3 = COR_TEXTO, TextXAlignment = Enum.TextXAlignment.Left,
	}, lateral)
	local listaAbas = novo("Frame", {
		Size = UDim2.new(1, -16, 1, -40), Position = UDim2.fromOffset(8, 34), BackgroundTransparency = 1,
	}, lateral)
	novo("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, listaAbas)

	-- Conteúdo
	local conteudo = novo("Frame", {
		Size = UDim2.new(1, -150, 1, -56), Position = UDim2.fromOffset(150, 56), BackgroundTransparency = 1,
	}, janela)
	local rotuloAba = novo("TextLabel", {
		Size = UDim2.new(1, -24, 0, 20), Position = UDim2.fromOffset(16, 8), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
	}, conteudo)
	acento(rotuloAba, "TextColor3")
	local scroll = novo("ScrollingFrame", {
		Size = UDim2.new(1, -20, 1, -40), Position = UDim2.fromOffset(10, 34),
		BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
	}, conteudo)
	novo("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)

	local ordem = 0
	local pintores = {}

	local function novaLinha(altura)
		ordem += 1
		local f = novo("Frame", {
			Size = UDim2.new(1, -6, 0, altura), BackgroundColor3 = COR_LINHA,
			BorderSizePixel = 0, LayoutOrder = ordem,
		}, scroll)
		canto(f, 6)
		return f
	end

	local function textos(f, titulo, desc, reservado)
		reservado = reservado or 100
		novo("TextLabel", {
			Size = UDim2.new(1, -reservado, 0, 16), Position = UDim2.fromOffset(12, desc and 7 or 14),
			BackgroundTransparency = 1, Text = titulo, Font = Enum.Font.GothamBold, TextSize = 12,
			TextColor3 = COR_TEXTO, TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, f)
		if desc then
			novo("TextLabel", {
				Size = UDim2.new(1, -reservado, 0, 12), Position = UDim2.fromOffset(12, 25),
				BackgroundTransparency = 1, Text = desc, Font = Enum.Font.Gotham, TextSize = 9,
				TextColor3 = COR_SUB, TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}, f)
		end
	end

	local function secao(texto)
		ordem += 1
		novo("TextLabel", {
			Size = UDim2.new(1, -6, 0, 20), BackgroundTransparency = 1, Text = texto,
			Font = Enum.Font.GothamBold, TextSize = 10, TextColor3 = COR_SUB,
			TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = ordem,
		}, scroll)
	end

	local function linhaToggle(titulo, desc, get, set)
		local f = novaLinha(44)
		textos(f, titulo, desc, 70)
		local pill = novo("Frame", {
			Size = UDim2.fromOffset(38, 20), AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0), BorderSizePixel = 0,
		}, f)
		canto(pill, 100)
		local knob = novo("Frame", {
			Size = UDim2.fromOffset(14, 14), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
		}, pill)
		canto(knob, 100)
		local ultimo, ultimoAc = nil, nil
		local function pintar()
			local on = get()
			if on == ultimo and ultimoAc == tema.acento then return end
			local primeiro = (ultimo == nil)
			ultimo, ultimoAc = on, tema.acento
			local cor = on and tema.acento or COR_OFF
			local pos = on and UDim2.fromOffset(21, 3) or UDim2.fromOffset(3, 3)
			if primeiro then
				pill.BackgroundColor3 = cor
				knob.Position = pos
			else
				local info = TweenInfo.new(0.12, Enum.EasingStyle.Quad)
				TweenService:Create(pill, info, { BackgroundColor3 = cor }):Play()
				TweenService:Create(knob, info, { Position = pos }):Play()
			end
		end
		pintar()
		table.insert(pintores, pintar)
		local clique = novo("TextButton", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 5,
		}, f)
		clique.Activated:Connect(function()
			seguro(set, not get())
			pintar()
		end)
	end

	local function linhaBotao(titulo, desc, textoFn, aoClicar)
		local f = novaLinha(44)
		textos(f, titulo, desc, 130)
		local b = novo("TextButton", {
			Size = UDim2.fromOffset(108, 26), AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0), BorderSizePixel = 0, Font = Enum.Font.GothamBold,
			TextSize = 10, TextColor3 = Color3.new(1, 1, 1), AutoButtonColor = true, ZIndex = 5,
		}, f)
		canto(b, 6)
		local function pintar()
			b.Text = textoFn()
			b.BackgroundColor3 = tema.acento
		end
		pintar()
		table.insert(pintores, pintar)
		b.Activated:Connect(function()
			seguro(aoClicar)
			pintar()
		end)
	end

	local function linhaInfo(titulo, tecla)
		local f = novaLinha(36)
		textos(f, titulo, nil, 120)
		local t = novo("TextLabel", {
			Size = UDim2.fromOffset(100, 18), AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -12, 0.5, 0), BackgroundTransparency = 1, Text = tecla,
			Font = Enum.Font.GothamBold, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right,
		}, f)
		acento(t, "TextColor3")
	end

	local function linhaTexto(getTexto, altura)
		local f = novaLinha(altura)
		local t = novo("TextLabel", {
			Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4), BackgroundTransparency = 1,
			Font = Enum.Font.Gotham, TextSize = 9, TextColor3 = COR_SUB, TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		}, f)
		local function pintar() t.Text = getTexto() end
		pintar()
		table.insert(pintores, pintar)
	end

	-- slider: um único par de ouvintes globais (sem acumular a cada troca de aba)
	local sliderMover = nil
	UserInputService.InputChanged:Connect(function(input)
		if sliderMover and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			sliderMover(input.Position.X)
		end
		if arrastandoJanela and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - inicioJ
			janela.Position = UDim2.new(posJ.X.Scale, posJ.X.Offset + d.X, posJ.Y.Scale, posJ.Y.Offset + d.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			arrastandoJanela = false
			if sliderMover then
				sliderMover = nil
				scroll.ScrollingEnabled = true
			end
		end
	end)

	local function linhaSlider(titulo, desc, minimo, maximo, get, set, fmt)
		local f = novaLinha(desc and 62 or 54)
		textos(f, titulo, desc, 90)
		local valorTxt = novo("TextLabel", {
			Size = UDim2.fromOffset(70, 16), AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -12, 0, 7), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
			TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right,
		}, f)
		acento(valorTxt, "TextColor3")
		local trilho = novo("Frame", {
			Size = UDim2.new(1, -24, 0, 6), Position = UDim2.new(0, 12, 1, -16),
			BackgroundColor3 = COR_OFF, BorderSizePixel = 0,
		}, f)
		canto(trilho, 100)
		local enchimento = novo("Frame", { BorderSizePixel = 0 }, trilho)
		canto(enchimento, 100)
		local bolinha = novo("Frame", {
			Size = UDim2.fromOffset(12, 12), AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
		}, trilho)
		canto(bolinha, 100)

		local function pintar()
			local v = get()
			local rel = math.clamp((v - minimo) / (maximo - minimo), 0, 1)
			enchimento.Size = UDim2.fromScale(rel, 1)
			enchimento.BackgroundColor3 = tema.acento
			bolinha.Position = UDim2.new(rel, 0, 0.5, 0)
			valorTxt.Text = fmt and fmt(v) or tostring(v)
		end
		pintar()
		table.insert(pintores, pintar)

		local function mover(x)
			local rel = math.clamp((x - trilho.AbsolutePosition.X) / math.max(trilho.AbsoluteSize.X, 1), 0, 1)
			seguro(set, math.floor(minimo + rel * (maximo - minimo) + 0.5))
			pintar()
		end
		local clique = novo("TextButton", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", ZIndex = 5,
		}, f)
		clique.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch then
				sliderMover = mover
				scroll.ScrollingEnabled = false
				mover(input.Position.X)
			end
		end)
	end

	------------------------------------------------------------
	-- Conteúdo de cada aba
	------------------------------------------------------------
	local descarregar
	local ABAS = {}

	ABAS.VISUALS = function()
		secao("ITEMS")
		linhaToggle("Highlight Items", "Rarity-colored boxes on items",
			function() return ESP_LIGADO end,
			function(v) if v ~= ESP_LIGADO then alternar() end end)
		linhaToggle("Loot Labels", "Item name, weight and value",
			function() return OPC.labels end, function(v) OPC.labels = v end)
		linhaSlider("Item Render Distance", "Max distance for item boxes & labels (0 = infinite)", 0, 500,
			function() return OPC.distancia end, function(v) OPC.distancia = v end)
		for _, r in ipairs(RARIDADES) do
			linhaToggle("Show " .. r.rotulo, "Rarity filter",
				function() return ativos[r.id] end,
				function(v)
					ativos[r.id] = v
					atualizarFiltro(r)
					reescanear()
				end)
		end

		secao("PLAYERS")
		linhaToggle("Ativar ESP", "Liga/desliga todo o ESP de players",
			function() return ESP_PLAYERS_ON end, function(v) ESP_PLAYERS_ON = v end)
		linhaToggle("ESP Name", "Nome, distância e time",
			function() return ESP_NOME end, function(v) ESP_NOME = v end)
		linhaToggle("ESP Chams", "Highlight nos players (verde) e monstro (vermelho)",
			function() return OPC.chams end, function(v) OPC.chams = v end)
		linhaToggle("ESP Skeleton", "Esqueleto nos players",
			function() return ESP_SKEL end, function(v) ESP_SKEL = v end)
		linhaToggle("Mostrar Players", "Inclui jogadores comuns",
			function() return SKEL_PLAYERS end, function(v) SKEL_PLAYERS = v end)
		linhaToggle("Mostrar Monstro", "Inclui o monstro",
			function() return SKEL_MONSTROS end, function(v) SKEL_MONSTROS = v end)

		secao("MONSTER SELECT")
		linhaToggle("Auto-detect monster", "Finds the one player with a different body",
			function() return AUTO_DETECTAR end, function(v) AUTO_DETECTAR = v end)
		for _, j in ipairs(Players:GetPlayers()) do
			if j ~= eu then
				linhaToggle(j.DisplayName .. "  @" .. j.Name, "Mark as monster",
					function() return MONSTROS_MANUAL[j.Name] == true end,
					function(v) MONSTROS_MANUAL[j.Name] = v or nil end)
			end
		end

		secao("CAMERA & LIGHT")
		linhaToggle("Fullbright", "Reduce darkness and atmosphere fog",
			function() return OPC.fullbright end,
			function(v)
				OPC.fullbright = v
				luz(v)
			end)
		linhaToggle("Custom FOV", "Override the camera field of view",
			function() return OPC.fovLigado end, function(v) OPC.fovLigado = v end)
		linhaSlider("FOV", nil, 40, 120,
			function() return OPC.fov end, function(v) OPC.fov = v end)
	end

	ABAS.COMBAT = function()
		secao("GENERAL")
		linhaBotao("My role", "Auto = detects if you are the monster",
			function() return OPC.papelModo end,
			function()
				local prox = { Auto = "Player", Player = "Monster", Monster = "Auto" }
				OPC.papelModo = prox[OPC.papelModo] or "Auto"
				OPC.papelAtual = calcularPapel()
			end)
		linhaTexto(function()
			return "Current role: " .. (OPC.papelAtual == "monstro" and "MONSTER" or "PLAYER")
				.. "  |  the options of this role are the ones active"
		end, 26)
		linhaBotao("Attack method", "Tool = equipped tool, Click = mouse click",
			function() return OPC.metodoAtk end,
			function()
				local prox = { Tool = "Click", Click = "Both", Both = "Tool" }
				OPC.metodoAtk = prox[OPC.metodoAtk] or "Both"
			end)
		linhaToggle("Ignore teammates", "Never attack players on your team",
			function() return OPC.ignorarTime end, function(v) OPC.ignorarTime = v end)

		secao("SPEED & ATTACK (active role)")
		linhaToggle("Speed", "Applies to the role you are right now",
			function() return PERFIL[OPC.papelAtual].speedOn end,
			function(v) PERFIL[OPC.papelAtual].speedOn = v end)
		linhaSlider("Walk speed", nil, 16, 150,
			function() return PERFIL[OPC.papelAtual].speed end,
			function(v) PERFIL[OPC.papelAtual].speed = v end)
		linhaBotao("Speed method", "WalkSpeed = normal, CFrame = if the game resets it",
			function() return OPC.metodoVel end,
			function() OPC.metodoVel = (OPC.metodoVel == "WalkSpeed") and "CFrame" or "WalkSpeed" end)
		linhaTexto(textoSpeed, 40)
		linhaToggle("Auto Attack", "Applies to the role you are right now",
			function() return PERFIL[OPC.papelAtual].atkOn end,
			function(v) PERFIL[OPC.papelAtual].atkOn = v end)

		for _, chave in ipairs({ "player", "monstro" }) do
			local p = PERFIL[chave]
			secao(chave == "player" and "PLAYER OPTIONS (you are a player)" or "MONSTER OPTIONS (you are the monster)")
			linhaToggle("Speed", "Change your walk speed",
				function() return p.speedOn end, function(v) p.speedOn = v end)
			linhaSlider("Walk speed", nil, 16, 150,
				function() return p.speed end, function(v) p.speed = v end)
			linhaToggle("Auto Attack", "Attacks when a target is in front of you",
				function() return p.atkOn end, function(v) p.atkOn = v end)
			linhaToggle("Target: Players", "Attack normal players",
				function() return p.atkPlayers end, function(v) p.atkPlayers = v end)
			linhaToggle("Target: Monster", "Attack the monster",
				function() return p.atkMonstro end, function(v) p.atkMonstro = v end)
			linhaSlider("Attack range", "Max distance to the target (studs)", 3, 40,
				function() return p.alcance end, function(v) p.alcance = v end)
			linhaSlider("Front angle", "Width of the cone in front of you", 10, 180,
				function() return p.angulo end, function(v) p.angulo = v end,
				function(v) return "±" .. v .. "°" end)
			linhaSlider("Attack delay", "Pause between attacks", 1, 20,
				function() return p.espera end, function(v) p.espera = v end,
				function(v) return (v / 10) .. "s" end)
		end
		linhaTexto(function() return "STATUS: " .. tostring(OPC.statusAtk) end, 40)
	end

	ABAS.MOVEMENT = function()
		linhaToggle("Auto Farm | L to start", "Teleport to marked items and collect them",
			function() return OPC.autoLoot end, function(v) OPC.autoLoot = v end)
		linhaBotao("Farm status", "Targets ready / collected  |  tap = retry skipped",
			function() return contarAlvos() .. " ready · " .. coletados .. " done" end,
			function() tentados = {} end)
		linhaToggle("Pause Near Monster", "Stop moving while the monster is close",
			function() return OPC.pausarMonstro end, function(v) OPC.pausarMonstro = v end)
		linhaSlider("Pause Distance", "Stops when the monster is closer than this", 10, 150,
			function() return OPC.distPausa end, function(v) OPC.distPausa = v end)
		linhaToggle("Distance Pause", "Stop for 5 seconds after traveling 300 studs",
			function() return OPC.pausaDistancia end, function(v) OPC.pausaDistancia = v end)
		linhaBotao("AutoFarm Movement", "Teleport = instant, Tween = glide, Pathfind = walk",
			function() return OPC.modo end,
			function()
				local prox = { Teleport = "Tween", Tween = "Pathfind", Pathfind = "Teleport" }
				OPC.modo = prox[OPC.modo] or "Teleport"
			end)
		linhaSlider("Teleport Delay", "Seconds to wait after each teleport", 1, 20,
			function() return OPC.tpDelay end, function(v) OPC.tpDelay = v end,
			function(v) return (v / 10) .. "s" end)
		linhaSlider("Max Item Weight", "Skip items heavier than this (kg)", 1, 80,
			function() return OPC.pesoMax end, function(v) OPC.pesoMax = v end)
		linhaSlider("Tween Speed", "Studs per second in Tween mode", 10, 120,
			function() return OPC.velocidade end, function(v) OPC.velocidade = v end)
		linhaToggle("Instant Interact", "Set ProximityPrompt hold duration to zero",
			function() return INSTANT_PP end,
			function(v)
				INSTANT_PP = v
				if v then escanearInstant() else restaurarInstant() end
			end)

		secao("BASKETBALL")
		linhaToggle("Auto Perfect Shoot", "Holds USAR for you and releases at PERFEITO",
			function() return OPC.autoTiro end, function(v) OPC.autoTiro = v end)
		linhaToggle("Auto Release", "If you hold USAR, releases when PERFEITO shows",
			function() return OPC.autoPerfeito end, function(v) OPC.autoPerfeito = v end)
		linhaBotao("Press method", "Touch / Mouse / Tool / Signal: try another if it fails",
			function() return OPC.metodoTiro end,
			function()
				local prox = { Touch = "Mouse", Mouse = "Tool", Tool = "Signal", Signal = "Touch" }
				OPC.metodoTiro = prox[OPC.metodoTiro] or "Touch"
			end)
		linhaSlider("Max hold time", "Releases after this even without PERFEITO", 2, 40,
			function() return OPC.tiroMax end, function(v) OPC.tiroMax = v end,
			function(v) return (v / 10) .. "s" end)
		linhaSlider("Shot delay", "Pause between shots", 2, 40,
			function() return OPC.tiroEspera end, function(v) OPC.tiroEspera = v end,
			function(v) return (v / 10) .. "s" end)
		linhaTexto(function() return "STATUS: " .. tostring(OPC.statusTiro) end, 64)
	end

	ABAS.WORLD = function()
		linhaToggle("Remove Vents", "Hide every \"Vent Entrance\" part and disable collision",
			function() return OPC.removerVents end,
			function(v)
				OPC.removerVents = v
				OPC.precisaScan = true
				OPC.reaplicar = true
			end)
		linhaToggle("Vent ESP", "Draw a box around every vent entrance",
			function() return OPC.ventESP end,
			function(v)
				OPC.ventESP = v
				OPC.precisaScan = true
			end)
		linhaToggle("Exit Door ESP", "Draw a box around the exit doors",
			function() return OPC.saidaESP end,
			function(v)
				OPC.saidaESP = v
				OPC.precisaScan = true
			end)
		linhaToggle("Exit Tracers", "Draw lines to the exit doors",
			function() return OPC.tracers end,
			function(v)
				OPC.tracers = v
				OPC.precisaScan = true
			end)
		linhaToggle("Anti Afk Kick", "Prevent Roblox from kicking you for being idle",
			function() return OPC.antiAfk end, function(v) OPC.antiAfk = v end)
		local nomesMin = { "ALL ITEMS", "UNCOMMON+", "RARE+", "LEGENDARY+", "MYTHIC" }
		linhaBotao("Minimum Rarity", "Cycle to hide lower tiers",
			function() return nomesMin[OPC.minRar] end,
			function()
				OPC.minRar = OPC.minRar % #nomesMin + 1
				for i, r in ipairs(RARIDADES) do
					ativos[r.id] = (i >= OPC.minRar)
					atualizarFiltro(r)
				end
				reescanear()
			end)
	end

	ABAS.KEYBINDS = function()
		linhaInfo("Show / hide this menu", "RIGHT CTRL")
		linhaInfo("Start / stop Auto Farm", "L")
		linhaInfo("Player ESP on / off", "K")
		linhaInfo("Auto Attack on / off", "J")
		linhaInfo("Speed on / off", "H")
		linhaInfo("Item ESP on / off", "RIGHT SHIFT")
		linhaInfo("Move the window", "DRAG THE HEADER")
		linhaInfo("Phone: open the menu", "MOON BUTTON")
	end

	ABAS.CUSTOMIZE = function()
		local f = novaLinha(56)
		textos(f, "Accent color", "Pick the menu color", 200)
		local cores = {
			Color3.fromRGB(110, 80, 255), Color3.fromRGB(50, 140, 255), Color3.fromRGB(255, 70, 90),
			Color3.fromRGB(60, 210, 120), Color3.fromRGB(255, 160, 40),
		}
		for i, c in ipairs(cores) do
			local b = novo("TextButton", {
				Size = UDim2.fromOffset(22, 22), AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10 - (#cores - i) * 28, 0.5, 0), BackgroundColor3 = c,
				Text = "", BorderSizePixel = 0, ZIndex = 5,
			}, f)
			canto(b, 100)
			b.Activated:Connect(function()
				tema.acento = c
				aplicarTema()
			end)
		end
		linhaSlider("Window opacity", nil, 40, 100,
			function() return OPC.opacidade end,
			function(v)
				OPC.opacidade = v
				janela.BackgroundTransparency = 1 - v / 100
			end,
			function(v) return v .. "%" end)
	end

	ABAS.CONFIGS = function()
		secao("PERFORMANCE")
		linhaTexto(function() return "FPS: " .. fpsAtual end, 26)
		linhaToggle("FPS Boost", "Lowest quality, no shadows, no particles or post effects",
			function() return OPC.fpsBoost end,
			function(v)
				OPC.fpsBoost = v
				fpsBoost(v)
			end)
		linhaToggle("Simplify Materials", "Every part becomes plain plastic (strong boost)",
			function() return OPC.materiaisSimples end,
			function(v)
				OPC.materiaisSimples = v
				simplificar(v)
			end)
		linhaToggle("Optimize ESP", "Slower refresh for skeletons, labels and chams",
			function() return OPC.otimizar end,
			function(v)
				OPC.otimizar = v
				OTIMIZAR = v
			end)
		linhaSlider("Skeleton max distance", "0 = unlimited (less drawing = more FPS)", 0, 1000,
			function() return SKEL_DIST end, function(v) SKEL_DIST = v end)

		secao("GENERAL")
		linhaToggle("Show NPC skeletons", "Also draw skeletons on non-player characters",
			function() return MOSTRAR_NPCS end,
			function(v)
				MOSTRAR_NPCS = v
				if v then
					escanearEsqueleto()
				else
					for model, dados in pairs(esqueletos) do
						if not dados.jogador then destruirEsqueleto(model) end
					end
				end
			end)
		linhaBotao("Scan shot GUI", "Shows what the script sees (send me a print)",
			function() return "SCAN" end,
			function() OPC.scanTexto = escanearTiro() end)
		linhaTexto(function() return OPC.scanTexto or "Hold USAR for a shot, then tap SCAN." end, 150)
		linhaBotao("Unload script", "Remove everything and stop all features",
			function() return "UNLOAD" end,
			function() descarregar() end)
	end

	local ABAS_NOMES = { "VISUALS", "COMBAT", "MOVEMENT", "WORLD", "KEYBINDS", "CUSTOMIZE", "CONFIGS" }
	local TITULOS = {
		VISUALS = "VISUALS", COMBAT = "COMBAT  /  SPEED & AUTO ATTACK", MOVEMENT = "MOVEMENT & INTERACTION", WORLD = "WORLD",
		KEYBINDS = "KEYBINDS", CUSTOMIZE = "CUSTOMIZE", CONFIGS = "CONFIGS",
	}
	local botoesAba = {}
	local abaAtual = "VISUALS"

	local function abrirAba(nome)
		abaAtual = nome
		for _, c in ipairs(scroll:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		pintores = {}
		ordem = 0
		rotuloAba.Text = TITULOS[nome]
		scroll.CanvasPosition = Vector2.new(0, 0)
		for n, b in pairs(botoesAba) do
			local sel = (n == nome)
			b.btn.BackgroundTransparency = sel and 0 or 1
			b.btn.TextColor3 = sel and COR_TEXTO or COR_SUB
			b.barra.Visible = sel
		end
		seguro(ABAS[nome])
	end

	for i, nome in ipairs(ABAS_NOMES) do
		local b = novo("TextButton", {
			Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = Color3.fromRGB(34, 28, 70),
			BackgroundTransparency = 1, BorderSizePixel = 0, Text = "   " .. nome,
			Font = Enum.Font.GothamBold, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = COR_SUB, AutoButtonColor = false, LayoutOrder = i,
		}, listaAbas)
		canto(b, 5)
		local barra = novo("Frame", {
			Size = UDim2.fromOffset(3, 20), Position = UDim2.new(0, 0, 0.5, -10),
			BorderSizePixel = 0, Visible = false,
		}, b)
		acento(barra, "BackgroundColor3")
		botoesAba[nome] = { btn = b, barra = barra }
		b.MouseEnter:Connect(function()
			if abaAtual ~= nome then b.BackgroundTransparency = 0.6 end
		end)
		b.MouseLeave:Connect(function()
			if abaAtual ~= nome then b.BackgroundTransparency = 1 end
		end)
		b.Activated:Connect(function() abrirAba(nome) end)
	end

	-- Botão flutuante (celular): toque abre/fecha, arraste move
	local bolha = novo("TextButton", {
		Size = UDim2.fromOffset(42, 42), Position = UDim2.new(0, 14, 0.35, 0),
		BackgroundColor3 = COR_FUNDO, Text = "🌙", Font = Enum.Font.GothamBold, TextSize = 24,
		AutoButtonColor = false, ZIndex = 20,
	}, gui)
	canto(bolha, 100)
	acento(bolha, "TextColor3")
	local contorno = novo("UIStroke", { Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, bolha)
	acento(contorno, "Color")

	local pressionado, moveu, iniB, posB = false, false, nil, nil
	bolha.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			pressionado, moveu = true, false
			iniB, posB = input.Position, bolha.Position
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if pressionado and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - iniB
			if d.Magnitude > 8 then moveu = true end
			if moveu then
				bolha.Position = UDim2.new(posB.X.Scale, posB.X.Offset + d.X, posB.Y.Scale, posB.Y.Offset + d.Y)
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if pressionado and (input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch) then
			pressionado = false
			if not moveu then janela.Visible = not janela.Visible end
		end
	end)

	descarregar = function()
		shared.ESP_SESSAO = nil
		OPC.removerVents = false
		OPC.fullbright = false
		seguro(luz, false)
		seguro(fpsBoost, false)
		OPC.fpsBoost = false
		OPC.materiaisSimples = false
		seguro(simplificar, false)
		seguro(aplicarVents, false)
		seguro(restaurarInstant)
		INSTANT_PP = false
		limparTudo()
		gui:Destroy()
		tela:Destroy()
	end

	-- Atalhos: Right Ctrl abre/fecha o menu, L liga/desliga o Auto Loot, K liga/desliga o ESP de players
	UserInputService.InputBegan:Connect(function(input, processado)
		if processado or not sessaoViva() then return end
		if input.KeyCode == Enum.KeyCode.RightControl then
			janela.Visible = not janela.Visible
		elseif input.KeyCode == Enum.KeyCode.L then
			OPC.autoLoot = not OPC.autoLoot
		elseif input.KeyCode == Enum.KeyCode.K then
			ESP_PLAYERS_ON = not ESP_PLAYERS_ON
		elseif input.KeyCode == Enum.KeyCode.J then
			local p = PERFIL[OPC.papelAtual]
			p.atkOn = not p.atkOn
		elseif input.KeyCode == Enum.KeyCode.H then
			local p = PERFIL[OPC.papelAtual]
			p.speedOn = not p.speedOn
		end
	end)

	-- mantém os switches em dia (ex.: Right Shift muda o ESP por fora do menu)
	task.spawn(function()
		while sessaoViva() do
			task.wait(0.4)
			if janela.Visible then
				for _, p in ipairs(pintores) do seguro(p) end
				seloTxt.Text = "● " .. fpsAtual .. " FPS"
				seloTxt.TextColor3 = (fpsAtual < 30) and Color3.fromRGB(255, 110, 110) or Color3.fromRGB(90, 230, 170)
			end
		end
	end)

	local function reabrirSeVisuals()
		if abaAtual == "VISUALS" and janela.Visible and sessaoViva() then abrirAba("VISUALS") end
	end
	Players.PlayerAdded:Connect(function() task.defer(reabrirSeVisuals) end)
	Players.PlayerRemoving:Connect(function() task.delay(0.2, reabrirSeVisuals) end)

	local function boasVindas()
		local card = novo("Frame", {
			Size = UDim2.fromOffset(270, 64), AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, -90), BackgroundColor3 = COR_FUNDO,
			BorderSizePixel = 0, ZIndex = 30,
		}, gui)
		canto(card, 10)
		local st = novo("UIStroke", { Thickness = 1.5 }, card)
		acento(st, "Color")
		local av = novo("ImageLabel", {
			Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(9, 9),
			BackgroundColor3 = COR_LINHA, BorderSizePixel = 0, Image = "", ZIndex = 31,
		}, card)
		canto(av, 100)
		usarAvatar(av)
		novo("TextLabel", {
			Size = UDim2.new(1, -74, 0, 20), Position = UDim2.fromOffset(64, 11),
			BackgroundTransparency = 1, Text = "Bem-vindo, " .. eu.DisplayName,
			Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = COR_TEXTO,
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 31,
		}, card)
		novo("TextLabel", {
			Size = UDim2.new(1, -74, 0, 14), Position = UDim2.fromOffset(64, 33),
			BackgroundTransparency = 1, Text = "@" .. eu.Name .. "  ·  ID " .. eu.UserId,
			Font = Enum.Font.Gotham, TextSize = 10, TextColor3 = COR_SUB,
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 31,
		}, card)
		TweenService:Create(card, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, 0, 0, 16) }):Play()
		task.delay(4.5, function()
			if not card.Parent then return end
			local t = TweenService:Create(card, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Position = UDim2.new(0.5, 0, 0, -90) })
			t:Play()
			t.Completed:Wait()
			card:Destroy()
		end)
	end

	abrirAba("VISUALS")
	seguro(boasVindas)
	tela.Enabled = false -- esconde o painel antigo (a lógica dele continua)
end

local okModulo, erroModulo = pcall(iniciarMaisOpcoes)
if not okModulo then
	warn("[ESP] erro no menu: " .. tostring(erroModulo))
	local pgErro = Players.LocalPlayer:FindFirstChild("PlayerGui")
	if pgErro then
		local g = Instance.new("ScreenGui")
		g.Name = "ESPErro"
		g.ResetOnSpawn = false
		g.DisplayOrder = 1000000
		local t = Instance.new("TextLabel")
		t.Size = UDim2.new(1, -20, 0, 90)
		t.Position = UDim2.fromOffset(10, 60)
		t.BackgroundColor3 = Color3.fromRGB(40, 0, 0)
		t.TextColor3 = Color3.new(1, 1, 1)
		t.TextWrapped = true
		t.TextSize = 14
		t.Text = "ERRO NO MENU NOVO (manda print): " .. tostring(erroModulo)
		t.Parent = g
		g.Parent = pgErro
	end
end

----------------------------------------------------------------
-- Início
----------------------------------------------------------------
atualizarBotao()

workspace.DescendantAdded:Connect(function(obj)
	if shared.ESP_SESSAO ~= SESSAO then return end
	local c = obj.ClassName
	if c ~= "ProximityPrompt" and c ~= "ClickDetector" and c ~= "Tool" and c ~= "Humanoid" and c ~= "Motor6D" then return end
	task.defer(function()
		pcall(aplicarInstant, obj)
		pcall(detectarEsqueleto, obj)
		pcall(verificar, obj)
	end)
end)

-- varredura inicial em segundo plano (não trava o início do jogo)
task.spawn(function()
	escanearInstant()
	escanearEsqueleto()
	escanear()
end)

CollectionService:GetInstanceAddedSignal("Item"):Connect(function(obj)
	marcar(obj)
end)

