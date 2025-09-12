-- Reactor Control GUI Installer (std libs only)
-- Author: P1KaChU337

------------------------------------ config ------------------------------------
local REPOSITORY  = "https://raw.githubusercontent.com/P1KaChU337/Reactor-Control-for-OpenComputers/refs/heads/main/"

local filesToDownload = {
  {url = REPOSITORY.."home/nr_v1.1.lua",                path="/home/main.lua"},
}
local newVer = "1.1.2"
local oldVer = "1.0"
local f = io.open("oldVersion.txt", "r")
if f then
  oldVer = f:read("*l") or "1.0"
  f:close()
  os.execute("rm oldVersion.txt > /dev/null 2>&1")
end
local appTitle = "Reactor Control v".. oldVer .. " --> v" .. newVer .. " — Updater"
local rebootAfter = true
-------------------------------------------------------------------------------
local computer  = require("computer")
local component = require("component")
local gpu       = component.gpu
local term      = require("term")
local event     = require("event")
local unicode   = require("unicode")
local shell     = require("shell")
local fs        = require("filesystem")
local computer  = require("computer")

-- colors
local COL_BG     = 0x0A0F0A
local COL_FRAME  = 0x0F1F0F
local COL_TEXT   = 0xDDFFDD
local COL_DIM    = 0x99CC99
local COL_WARN   = 0xFFD37F
local COL_ERR    = 0xFF6B6B
local COL_OK     = 0x7CFF7C
local COL_BARBG  = 0x123312
local COL_BAR    = 0x22FF88

-- save/restore screen state
local sw, sh = gpu.getResolution()
local oldBG, oldFG = gpu.getBackground(), gpu.getForeground()

local function safeSetBG(c) gpu.setBackground(c) end
local function safeSetFG(c) gpu.setForeground(c) end

local function fill(x,y,w,h,bg)
  safeSetBG(bg); gpu.fill(x,y,w,h," ")
end

local function text(x,y,str,fg)
  if fg then safeSetFG(fg) end
  gpu.set(x,y,str)
end

local function centerX(w) return math.floor((sw - w)/2)+1 end
local function centerY(h) return math.floor((sh - h)/2)+1 end

local function frame(x,y,w,h)
  safeSetFG(COL_DIM)
  gpu.set(x,y,       "┌"..string.rep("─",w-2).."┐")
  for i=1,h-2 do gpu.set(x,y+i,"│"..string.rep(" ",w-2).."│") end
  gpu.set(x,y+h-1,   "└"..string.rep("─",w-2).."┘")
end

local function progressBar(x,y,w,ratio)
  local full = math.max(0, math.min(w, math.floor(w*ratio)))
  safeSetBG(COL_BARBG); gpu.fill(x,y,w,1," ")
  safeSetBG(COL_BAR);   gpu.fill(x,y,full,1," ")
  safeSetBG(COL_BG)
end

local function shorten(str,maxLen)
  if unicode.len(str) <= maxLen then return str end
  return unicode.sub(str,1,maxLen-3).."..."
end

-- layout
local W, H = 70, 22
local X, Y = centerX(W), centerY(H)
local PAD  = 2

local function drawChrome()
  term.clear()
  safeSetBG(COL_BG); fill(1,1,sw,sh,COL_BG)
  fill(X,Y,W,H,COL_FRAME)
  frame(X,Y,W,H)
  -- title
  text(X+2, Y, "┤ "..appTitle.." ├", COL_TEXT)
  text(X+W-20, Y, "[by P1KaChU337]", COL_DIM)
  -- логотип
  text(X+W-15, Y+1, "☢ REACTOR", COL_WARN)
  -- секции
  text(X+2, Y+2, "Status:", COL_DIM)
  text(X+2, Y+6, "Progress:", COL_DIM)
  text(X+2, Y+9, "Log:", COL_DIM)
  fill(X+2, Y+7, W-4, 1, COL_BARBG)
end

local function writeStatus(msg, color)
  fill(X+2, Y+3, W-4, 2, COL_FRAME)
  text(X+2, Y+3, shorten(msg,W-6), color or COL_TEXT)
end

local logTop, logHeight = Y+10, H-11
local logLines = {}

local function log(msg, color)
  color = color or COL_TEXT
  if #logLines >= logHeight then table.remove(logLines,1) end
  table.insert(logLines, shorten(msg,W-6))
  for i=1,logHeight do
    fill(X+2, logTop+i-1, W-4, 1, COL_FRAME)
    local ln = logLines[i]
    if ln then text(X+2, logTop+i-1, ln, color) end
  end
end

local spinner = {"⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"}
local spinIdx = 1
local function tickSpinner()
  local s = spinner[spinIdx]; spinIdx = spinIdx % #spinner + 1
  text(X+W-4, Y+3, s, COL_DIM)
end

local function ensureDirs()
  if not fs.exists("/lib/FormatModules") then fs.makeDirectory("/lib/FormatModules") end
  if not fs.exists("/home/images/") then fs.makeDirectory("/home/images/") end
end

local function install()
  drawChrome()
  ensureDirs()
  writeStatus("Initializing installer…", COL_DIM)
  log("Preparing directories…", COL_DIM)

  local total = #filesToDownload
  local okCount, failCount = 0, 0

  for i, f in ipairs(filesToDownload) do
    local label = string.format("[%02d/%02d] %s", i, total, shorten(f.path,30))
    writeStatus("Downloading "..label, COL_TEXT)
    log("wget "..shorten(f.url,45), COL_DIM)

    local res = shell.execute("wget -fq "..f.url.." "..f.path)
    tickSpinner()

    if res then
      okCount = okCount + 1
      log("OK: "..shorten(f.path,45), COL_OK)
    else
      failCount = failCount + 1
      log("ERROR: "..shorten(f.url,45), COL_ERR)
    end

    local ratio = i/total
    progressBar(X+2, Y+7, W-4, ratio)
    text(X+2, Y+8, string.format("Progress: %d%%  OK:%d  Fail:%d",
      math.floor(ratio*100), okCount, failCount), COL_DIM)
  end

  local f = io.open("/home/.shrc","w")
  if f then f:write("main.lua\n"); f:close() end
  log("Autostart set: /home/.shrc -> main.lua", COL_OK)

  if failCount == 0 then
    writeStatus("Update v".. oldVer .." --> v" .. newVer .." complete! All OK.", COL_OK)
  else
    writeStatus("Completed with errors. Check log.", COL_WARN)
  end

  text(X+2, Y+H-2, "by P1KaChU337 | Reactor Control Updater", COL_DIM)

  if rebootAfter then
    for n=5,1,-1 do
      text(X+W-20, Y+H-2, ("Reboot in %d..."):format(n), COL_TEXT)
      os.sleep(1)
    end
    shell.execute("reboot")
  else
    text(X+2, Y+H-2, "Press any key to exit…", COL_TEXT)
    event.pull("key_down")
  end
end

local ok, err = pcall(install)
safeSetBG(oldBG); safeSetFG(oldFG)
if not ok then
  term.clear()
  io.stderr:write("Installer crashed: "..tostring(err).."\n")
end





