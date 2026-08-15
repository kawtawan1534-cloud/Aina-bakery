# ===== Parallel Engine Core — Version: 6.9.0 =====
# ไฟล์นี้คือ orchestrator ตัวจริง (รันได้จริง) — เชื่อมไฟล์ layer ใน Layers\
# เข้าด้วยกันตามลำดับ pipeline แล้วสั่งรัน ไม่ใช่ตัวคำนวณเอง (ตัวคำนวณอยู่ใน
# แต่ละไฟล์ layer) Engine Noname.txt เป็น snapshot pseudocode เก่าไว้อ่าน
# อ้างอิงเท่านั้น ไม่ใช่ตัวจริง ดู Patch_Log.txt สำหรับเหตุผล/ประวัติทุกการ
# เปลี่ยนแปลง (ไฟล์นี้เก็บแค่โค้ดปัจจุบัน ไม่เก็บประวัติ)
# Pipeline: productionPlan -> normalizeStock -> core -> outputProduction ->
#           customerLayer -> salesLayer -> reorderLayer -> operatingExpenses ->
#           outputSales

param(
  [int]$TargetDay = 6,
  [string]$StatePath = "$PSScriptRoot\sim_state.json",
  [string]$ReportPath = "$PSScriptRoot\sim_report.json",
  [string]$LogPath = "$PSScriptRoot\sim_daily_log.json"
)

# ===== โหลดข้อมูลดิบจากไฟล์อ้างอิง =====
# recipe/costRates/prices/stockMax/reorderThreshold มาจาก JSON เท่านั้น ไม่มี
# ค่าดิบซ้ำอยู่ในไฟล์นี้เลย — ถ้าไฟล์ข้อมูลหาย/ขาด key ที่ต้องใช้ throw error
# ทันที (แบบ Excel #REF!) ไม่คำนวณต่อแบบเงียบๆ ด้วยค่าที่อาจผิด
function ConvertTo-Hashtable($obj) {
  $ht = @{}
  foreach ($p in $obj.PSObject.Properties) {
    if ($p.Value -is [System.Management.Automation.PSCustomObject]) {
      $ht[$p.Name] = ConvertTo-Hashtable $p.Value
    } else {
      $ht[$p.Name] = $p.Value
    }
  }
  return $ht
}

function Read-DataFile($path, $label) {
  if (-not (Test-Path $path)) { throw "ไม่พบไฟล์ข้อมูล: $path (จำเป็นสำหรับ $label)" }
  $data = Get-Content $path -Raw | ConvertFrom-Json
  if (-not $data) { throw "อ่านไฟล์ $path ไม่ได้ หรือไฟล์ว่างเปล่า (จำเป็นสำหรับ $label)" }
  return $data
}

$recipeFile = Read-DataFile "$PSScriptRoot\Raw Data\Production Recipe per Piece.json" "recipe/costRates"
$recipe = ConvertTo-Hashtable $recipeFile.recipe
$costRates = ConvertTo-Hashtable $recipeFile.costRates

$productionFile = Read-DataFile "$PSScriptRoot\Raw Data\Production.json" "prices"
$prices = @{}
foreach ($p in $productionFile.menu.PSObject.Properties) {
  if (-not $p.Value.locked) { $prices[$p.Name] = $p.Value.price }
}

$stockFile = Read-DataFile "$PSScriptRoot\Raw Data\Stock เริ่มต้น.json" "stockMax/unitScale/reorderThreshold/initialCash"
$stockMax = ConvertTo-Hashtable $stockFile.stockMax
$unitScale = ConvertTo-Hashtable $stockFile.unitScale
$reorderThreshold = ConvertTo-Hashtable $stockFile.reorderThreshold
$initialCash = [double]$stockFile.initialCash

# เช็คว่าข้อมูลข้ามไฟล์ครบพอคำนวณจริงได้ (เมนูที่ปลดล็อกทุกตัวต้องมี recipe,
# recipe ทุกวัตถุดิบต้องมี costRates, และมี stockMax ยกเว้นไข่ที่หน่วยฟองอยู่แล้ว)
foreach ($item in $prices.Keys) {
  if (-not $recipe.ContainsKey($item)) { throw "recipe ไม่มีเมนู '$item' (มีใน Production.json แต่ไม่มีใน Production Recipe per Piece.json)" }
  foreach ($mat in $recipe[$item].Keys) {
    if (-not $costRates.ContainsKey($mat)) { throw "costRates ไม่มีวัตถุดิบ '$mat' (ใช้ในสูตร $item)" }
    if ($mat -ne "egg" -and -not $stockMax.ContainsKey($mat)) { throw "stockMax ไม่มีวัตถุดิบ '$mat' (ใช้ในสูตร $item)" }
    if ($mat -ne "egg" -and -not $reorderThreshold.ContainsKey($mat)) { throw "reorderThreshold ไม่มีวัตถุดิบ '$mat' (ใช้ในสูตร $item)" }
  }
}
# ทุกวัตถุดิบในคลังต้องประกาศตัวคูณหน่วยไว้ ไม่งั้น Normalize-Stock() จะได้ค่า null
# แล้วคำนวณต่อเงียบๆ เหมือนวัตถุดิบหมด (ผลิตไม่ได้เลยโดยไม่มีอะไรเตือน)
foreach ($mat in $stockMax.Keys) {
  if (-not $unitScale.ContainsKey($mat)) { throw "unitScale ไม่มีวัตถุดิบ '$mat' (มีใน stockMax แต่ไม่ได้ประกาศตัวคูณหน่วย)" }
}

# ===== เชื่อม layer ทั้ง 8 เข้ากับ orchestrator (dot-source เข้า scope เดียวกัน) =====
# ลำดับ dot-source ไม่กระทบผลลัพธ์ (ฟังก์ชันอ่านตัวแปรตอนถูกเรียก ไม่ใช่ตอน
# นิยาม) แต่เรียงเลข 01-09 ตาม pipeline ไว้เพื่อให้คนอ่านตามลำดับง่าย
. "$PSScriptRoot\Layers\01_AutoProductionOrder.ps1"
. "$PSScriptRoot\Layers\02_NormalizeStock.ps1"
. "$PSScriptRoot\Layers\03_StockCheck.ps1"
. "$PSScriptRoot\Layers\04_OutputProduction.ps1"
. "$PSScriptRoot\Layers\05_CustomerLayer.ps1"
. "$PSScriptRoot\Layers\06_SalesLayer.ps1"
. "$PSScriptRoot\Layers\07_ReorderLayer.ps1"
. "$PSScriptRoot\Layers\08_OperatingExpenses.ps1"
. "$PSScriptRoot\Layers\09_OutputSales.ps1"

# ===== โหลด/สร้าง state =====
$items = @($prices.Keys)

if (Test-Path $StatePath) {
  $saved = Get-Content $StatePath -Raw | ConvertFrom-Json
  # เซฟที่ engine เขียนเองมี field ครบทุกตัวเสมอ ถ้าขาดแปลว่าไฟล์เสีย/แก้มือผิด
  # -> throw ทันที ดีกว่าเดินเกมต่อด้วยค่าที่หายไปเงียบๆ
  foreach ($f in @("stock","cash","history","lastDay","prevOrder","producedLast","soldLast","walkedAwayHistory","consecutiveDays")) {
    if (-not ($saved.PSObject.Properties.Name -contains $f)) { throw "sim_state.json ขาด field '$f' (เซฟไม่สมบูรณ์)" }
  }
  $stock = @{}
  foreach ($p in $saved.stock.PSObject.Properties) { $stock[$p.Name] = [double]$p.Value }
  $cash = [double]$saved.cash
  $history = @($saved.history)
  $lastDay = [int]$saved.lastDay
  $walkedAwayHistory = @($saved.walkedAwayHistory)
  $prevOrder = @{}
  foreach ($p in $saved.prevOrder.PSObject.Properties) { $prevOrder[$p.Name] = [double]$p.Value }
  $producedLast = @{}
  foreach ($p in $saved.producedLast.PSObject.Properties) { $producedLast[$p.Name] = [double]$p.Value }
  $soldLast = @{}
  foreach ($p in $saved.soldLast.PSObject.Properties) { $soldLast[$p.Name] = [double]$p.Value }
  $consecutiveDays = @{}
  foreach ($p in $saved.consecutiveDays.PSObject.Properties) { $consecutiveDays[$p.Name] = [int]$p.Value }
  $staleStock1 = @{}
  if ($saved.PSObject.Properties.Name -contains "staleStock1") {
    foreach ($p in $saved.staleStock1.PSObject.Properties) { $staleStock1[$p.Name] = [double]$p.Value }
  } else {
    foreach ($it in $items) { $staleStock1[$it] = 0 }
  }
  $staleStock2 = @{}
  if ($saved.PSObject.Properties.Name -contains "staleStock2") {
    foreach ($p in $saved.staleStock2.PSObject.Properties) { $staleStock2[$p.Name] = [double]$p.Value }
  } else {
    foreach ($it in $items) { $staleStock2[$it] = 0 }
  }
  # (Patch Draft "N/p growth" ปลดล็อก 2026-08-14) — field ใหม่ ถ้าเซฟเก่าไม่มีให้ตั้งค่าเริ่มต้น
  $shopRating = if ($saved.PSObject.Properties.Name -contains "shopRating") { [double]$saved.shopRating } else { 50.0 }
  $consecutiveGoodDays = if ($saved.PSObject.Properties.Name -contains "consecutiveGoodDays") { [int]$saved.consecutiveGoodDays } else { 0 }
  # (แก้บัค AutoProductionOrder มองไม่เห็นสต็อกเก่า 2026-08-14) — เก็บว่าเมื่อวาน
  # ขายของเก่า (stale1+stale2) ไปเท่าไหร่ต่อเมนู ถ้าเซฟเก่าไม่มีให้ตั้ง 0 (สมมติ
  # ไม่มีของเก่าช่วยขายเลยตอนย้ายเซฟเก่ามาใช้ ปลอดภัยกว่าเดา)
  $oldStockSoldLast = @{}
  if ($saved.PSObject.Properties.Name -contains "oldStockSoldLast") {
    foreach ($p in $saved.oldStockSoldLast.PSObject.Properties) { $oldStockSoldLast[$p.Name] = [double]$p.Value }
  } else {
    foreach ($it in $items) { $oldStockSoldLast[$it] = 0 }
  }
  # (แก้ "วงจรแกว่งสวนทางกัน" 2026-08-14 — ผู้เล่นสั่ง) เดิม AutoProductionOrder()
  # ดูแค่เมื่อวานวันเดียว อ่อนไหวต่อวันที่ผิดปกติมาก (เช่น Day144 ลูกค้าพุ่ง 18
  # คนพอดีวันที่เพิ่งตัดยอดสั่งฮวบ) เก็บประวัติย้อนหลังสูงสุด 3 วันต่อเมนู มา
  # เฉลี่ยแทน ลดความอ่อนไหวต่อวันเดียวโดยไม่ต้องแอบดูอนาคต (ใช้แค่ข้อมูลจริงที่
  # เกิดขึ้นแล้ว) — เซฟเก่าไม่มี field พวกนี้ให้เริ่มจาก array ว่าง (ตกกลับไปใช้
  # ค่าวันเดียวเหมือนเดิมจนกว่าจะสะสมประวัติครบ)
  $producedHist = @{}; $soldHist = @{}; $oldStockSoldHist = @{}; $orderedHist = @{}
  foreach ($it in $items) {
    $producedHist[$it] = if ($saved.PSObject.Properties.Name -contains "producedHist" -and $saved.producedHist.PSObject.Properties.Name -contains $it) { @($saved.producedHist.$it | ForEach-Object { [double]$_ }) } else { @() }
    $soldHist[$it] = if ($saved.PSObject.Properties.Name -contains "soldHist" -and $saved.soldHist.PSObject.Properties.Name -contains $it) { @($saved.soldHist.$it | ForEach-Object { [double]$_ }) } else { @() }
    $oldStockSoldHist[$it] = if ($saved.PSObject.Properties.Name -contains "oldStockSoldHist" -and $saved.oldStockSoldHist.PSObject.Properties.Name -contains $it) { @($saved.oldStockSoldHist.$it | ForEach-Object { [double]$_ }) } else { @() }
    # (แก้บัค "ยอดสั่งค้าง" 2026-08-14 — ผู้เล่นสั่งด่วน) เดิมเฉลี่ยแค่
    # produced/sold แต่ยังเทียบกับ $ordered ของเมื่อวานวันเดียว (คนละไทม์เฟรม
    # กัน) ทำให้เงื่อนไข "โต" ไม่ผ่านง่ายๆ แล้วค้างที่ยอดต่ำสุดไม่ขยับ (Day149
    # ค้างที่ 1/1/1 ทั้งที่ของหมดเกลี้ยง 2 วันติด) — เก็บประวัติยอดสั่งย้อนหลัง
    # 3 วันด้วย ให้ทุกตัวอยู่บนไทม์เฟรมเดียวกันหมด
    $orderedHist[$it] = if ($saved.PSObject.Properties.Name -contains "orderedHist" -and $saved.orderedHist.PSObject.Properties.Name -contains $it) { @($saved.orderedHist.$it | ForEach-Object { [double]$_ }) } else { @() }
  }
} else {
  $stock = @{}
  foreach ($k2 in $stockMax.Keys) { $stock[$k2] = $stockMax[$k2] }
  $cash = $initialCash # จาก Stock เริ่มต้น.json
  $history = @()
  $walkedAwayHistory = @()
  $lastDay = 0
  $prevOrder = @{}
  foreach ($it in $items) { $prevOrder[$it] = 5 }
  $producedLast = @{}
  $soldLast = @{}
  $consecutiveDays = @{}
  foreach ($it in $items) { $consecutiveDays[$it] = 0 }
  $staleStock1 = @{}
  $staleStock2 = @{}
  foreach ($it in $items) { $staleStock1[$it] = 0; $staleStock2[$it] = 0 }
  $shopRating = 50.0
  $consecutiveGoodDays = 0
  $oldStockSoldLast = @{}
  foreach ($it in $items) { $oldStockSoldLast[$it] = 0 }
  $producedHist = @{}; $soldHist = @{}; $oldStockSoldHist = @{}; $orderedHist = @{}
  foreach ($it in $items) { $producedHist[$it] = @(); $soldHist[$it] = @(); $oldStockSoldHist[$it] = @(); $orderedHist[$it] = @() }
}

# (Patch Draft "N/p growth" ปลดล็อก 2026-08-14, ตัด milestone ออก Patch 6.6.1,
# ตัดเพดาน N ออก Patch 6.6.2) — N/p ไม่ใช่ค่าคงที่ตายตัวอีกต่อไป ทั้งคู่
# คำนวณจาก $shopRating ล้วนๆ แบบต่อเนื่องทุกวัน มี lag 1 วันเสมอ (ใช้
# shopRating ของเมื่อวานตอนต้นลูป แล้วอัปเดตใหม่ท้ายลูป) เหมือน
# AutoProductionOrder() — บั๊กวงจรแกว่งที่รู้อยู่แล้วยังไม่แก้ ดู Patch Draft.txt
# N ไม่มี clamp เทียมของตัวเองอีกต่อไป (ผู้เล่นสั่ง: "ทำไมยังมีเพดาน" — ไม่ควร
# มีเพดานลอยๆ ที่ไอใส่เพิ่มเอง) ตัวจำกัดตามธรรมชาติมีอยู่แล้วในตัวสูตร: shopRating
# เองถูกคลัมป์ 0-100 อยู่แล้ว (บรรทัดคำนวณ shopRating ท้ายลูป) จึงทำให้ N ไหลอยู่
# ในช่วง 10-50 คนโดยอัตโนมัติแค่จาก "ชื่อเสียงมีเพดานจริงของมันเอง" ไม่ใช่จาก
# ไอไปจำกัด N ตรงๆ อีกชั้น
$customerPoolN = [Math]::Round(30 + (($shopRating - 50) * 0.4))
$customerVisitP = [Math]::Max(0.05, [Math]::Min(0.95, 0.35 + (($shopRating - 50) * 0.003) + ([Math]::Min(20, $consecutiveGoodDays * 0.5) * 0.005)))
$walkAwayChance = 0.05
# (Patch 6.5.1) เดิมสุ่มทั้งวันว่าเปิดโปร "ซื้อคู่คุ้มกว่า" มั้ย (10%/วัน) — เปลี่ยน
# เป็นเปิดโปรถาวรทุกวันแทน สุ่มแค่ระดับลูกค้าแต่ละคนว่าสนใจโปรมั้ย (ผ่าน
# $bundleAttemptChance ใน 06_SalesLayer.ps1) เพราะโปรนี้คือกลไกกันของเสีย
# ไม่ใช่อีเวนต์พิเศษที่ควรสุ่มเปิด-ปิดทั้งร้าน ดู Patch_Log.txt
$k = 1.5 # ระดับความสำคัญของราคาใน weighted preference (SalesLayer อ่านค่านี้)

# stockMax ไม่เปลี่ยนระหว่างเกม แปลงหน่วย/คิดเกณฑ์ครั้งเดียวพอ ไม่ต้องซ้ำทุกวัน
$stockMaxNorm = Normalize-Stock $stockMax
$threshNorm = @{}
foreach ($m in $stockMaxNorm.Keys) { $threshNorm[$m] = $reorderThreshold[$m] * $stockMaxNorm[$m] }

$dayReports = @()

for ($day = ($lastDay + 1); $day -le $TargetDay; $day++) {
  $cashStart = $cash
  $stockBeforeNorm = Normalize-Stock $stock

  # currentLeftoverStock = สต็อกเก่าที่ยังค้างอยู่จริง ณ ตอนตัดสินใจ (staleStock1+
  # staleStock2 ก่อนถูกอัปเดตท้ายลูปวันนี้) ให้ AutoProductionOrder() หักออกจาก
  # ยอดสั่งใหม่ ไม่ให้สั่งซ้อนทับของเก่าที่ขายไม่ออกอยู่แล้ว
  $currentLeftoverStock = @{}
  foreach ($it in $items) { $currentLeftoverStock[$it] = $staleStock1[$it] + $staleStock2[$it] }

  # เฉลี่ยประวัติย้อนหลังสูงสุด 3 วัน แทนใช้แค่เมื่อวานวันเดียว (ลดความอ่อนไหว
  # ต่อวันผิดปกติเดี่ยวๆ) — ถ้ายังไม่มีประวัติสะสม (เกมใหม่/เพิ่ง merge patch)
  # ตกกลับไปใช้ค่าวันเดียวล่าสุดเหมือนเดิมโดยอัตโนมัติ
  # (แก้บัค "ยอดสั่งค้าง" 2026-08-14) — เฉลี่ย $ordered (ยอดสั่งย้อนหลัง) ด้วย
  # เหมือนกัน ไม่ใช่แค่ produced/sold ไม่งั้นเทียบกันคนละไทม์เฟรม (ค่าเฉลี่ย
  # หลายวัน vs ค่าเดี่ยวเมื่อวาน) ทำให้เงื่อนไข "โต" ไม่ผ่านง่ายๆ แล้วค้างที่
  # ยอดต่ำสุดไม่ขยับ — ตอนนี้ทั้ง ordered/produced/sold อยู่บนไทม์เฟรมเดียวกัน
  $avgOrdered = @{}; $avgProduced = @{}; $avgSold = @{}; $avgOldStockSold = @{}
  foreach ($it in $items) {
    $avgOrdered[$it] = if ($orderedHist[$it].Count -gt 0) { ($orderedHist[$it] | Measure-Object -Average).Average } else { $prevOrder[$it] }
    $avgProduced[$it] = if ($producedHist[$it].Count -gt 0) { ($producedHist[$it] | Measure-Object -Average).Average } else { $producedLast[$it] }
    $avgSold[$it] = if ($soldHist[$it].Count -gt 0) { ($soldHist[$it] | Measure-Object -Average).Average } else { $soldLast[$it] }
    $avgOldStockSold[$it] = if ($oldStockSoldHist[$it].Count -gt 0) { ($oldStockSoldHist[$it] | Measure-Object -Average).Average } else { $oldStockSoldLast[$it] }
  }
  # (แก้ "สูตรไม่มีสามัญสำนึกเรื่องขนาดตลาด" 2026-08-14 — ผู้เล่นสั่ง ยังไม่รัน)
  # $customerPoolN/$customerVisitP ตอนนี้คือค่าที่คำนวณจบไปแล้วตั้งแต่ท้ายวัน
  # ก่อนหน้า (มาจากชื่อเสียงที่จบไปแล้ว) ไม่ใช่ค่าที่จะเกิดในอนาคตของวันนี้ —
  # ใช้เป็นพื้นขั้นต่ำของยอดสั่งได้อย่างสมเหตุสมผล หารเฉลี่ยเท่าๆ กันต่อเมนู
  # (ประมาณคร่าวๆ ไม่ได้แยกตามสัดส่วนราคา/ความนิยมจริง เพื่อความง่ายก่อน)
  $expectedCustomersToday = $customerPoolN * $customerVisitP
  $marketFloorPerItem = @{}
  foreach ($it in $items) { $marketFloorPerItem[$it] = [Math]::Max(1, [Math]::Floor($expectedCustomersToday / $items.Count)) }
  $productionOrder = AutoProductionOrder $avgOrdered $avgProduced $avgSold $avgOldStockSold $currentLeftoverStock $marketFloorPerItem $items

  $check = StockCheck $stock $productionOrder
  $prod = OutputProduction $check

  $ratios = @{}
  foreach ($m in $check.needed.Keys) { $ratios[$m] = $stockBeforeNorm[$m] / $check.needed[$m] }

  foreach ($item in $check.actualProduced.Keys) {
    foreach ($mat in $recipe[$item].Keys) {
      if ($mat -eq "egg") { continue }
      $usedG = $recipe[$item][$mat] * $check.actualProduced[$item]
      # ปัด 6 ตำแหน่งกัน floating point คลาดเคลื่อนสะสมจนค่าที่ควรเท่ากันพอดี
      # (ratio ควรเป็น 1.0) ต่ำกว่า 1 นิดเดียวแล้วโดน floor() ปัดทั้งที่ไม่ควรขาด
      $stock[$mat] = [Math]::Round($stock[$mat] - ($usedG / 1000), 6)
    }
  }
  $stock.egg -= $check.eggActual

  # (โปรดึงลูกค้าเข้าร้าน 2026-08-14 — ผู้เล่นสั่ง ยังไม่รัน/ยังไม่ทดสอบ) ถ้า
  # วันนี้มีทั้งของสด+ของเก่าค้าง (เข้าเงื่อนไขโปรซื้อคู่คุ้มกว่าได้จริง) ให้บวก
  # p bonus เล็กน้อยก่อนสุ่มลูกค้า — คนที่ปกติอาจไม่แวะ เห็นว่ามีโปรน่าจะคุ้ม
  # เลยตัดสินใจเข้ามาดู (แค่เพิ่มโอกาส "แวะร้าน" เท่านั้น ไม่ได้การันตีว่าจะ
  # ซื้อโปรจริง — ชั้นตัดสินใจซื้อจริงอยู่ใน SalesLayer แยกอิสระกัน)
  $hasFreshToday = (($check.actualProduced.Values | Measure-Object -Sum).Sum) -gt 0
  $hasStaleToday = ((($staleStock1.Values | Measure-Object -Sum).Sum) + (($staleStock2.Values | Measure-Object -Sum).Sum)) -gt 0
  $promoAvailableToday = $hasFreshToday -and $hasStaleToday
  $promoPBonus = if ($promoAvailableToday) { 0.03 } else { 0.0 }
  $customerVisitPToday = [Math]::Max(0.05, [Math]::Min(0.95, $customerVisitP + $promoPBonus))

  $custGen = GenerateDailyCustomers $customerPoolN $customerVisitPToday
  $customers = $custGen.customers
  $history += $customers # เก็บไว้แค่ดูเทรนด์ย้อนหลังในรายงาน ไม่ป้อนกลับเข้าสูตรคำนวณอีกต่อไป

  # [Diminishing Appeal] นับวันติดต่อกันที่แต่ละเมนู "ขายไม่หมด" เมื่อวาน
  foreach ($it in $items) {
    $prodY = if ($producedLast.ContainsKey($it)) { $producedLast[$it] } else { 0 }
    $soldY = if ($soldLast.ContainsKey($it)) { $soldLast[$it] } else { 0 }
    if ($prodY -gt 0 -and $soldY -lt $prodY) {
      $consecutiveDays[$it] = $consecutiveDays[$it] + 1
    } else {
      $consecutiveDays[$it] = 0
    }
  }
  $appealDecay = @{}
  foreach ($it in $items) { $appealDecay[$it] = [Math]::Max(0.6, 1 - 0.03 * $consecutiveDays[$it]) }

  # [Daily Hype Item] สุ่มเลือก 1 เมนูจากที่ผลิตวันนี้ ให้ weight โบนัส 1.5x
  $producedToday = @($items | Where-Object { $check.actualProduced.ContainsKey($_) -and $check.actualProduced[$_] -gt 0 })
  $hypeItem = if ($producedToday.Count -gt 0) { $producedToday[(Get-Random -Minimum 0 -Maximum $producedToday.Count)] } else { $null }

  $bundlePromoActive = $true # เปิดถาวร (Patch 6.5.1) — ดูเหตุผลที่หัวสคริปต์

  $availableStock = @{}
  foreach ($k3 in $check.actualProduced.Keys) { $availableStock[$k3] = $check.actualProduced[$k3] }
  $sales = SalesLayer $customers $availableStock $staleStock1 $staleStock2 $hypeItem $appealDecay $walkAwayChance $bundlePromoActive
  $walkedAwayHistory += $sales.walkedAway

  $discardedToday = @{}
  $discardWasteBaht = 0.0
  foreach ($it in $items) {
    $discardedToday[$it] = $staleStock2[$it]
    $discardWasteBaht += $staleStock2[$it] * $prod.unitCost[$it]
  }
  $newStaleStock2 = @{}
  $newStaleStock1 = @{}
  foreach ($it in $items) {
    $newStaleStock2[$it] = $staleStock1[$it]
    $newStaleStock1[$it] = $availableStock[$it]
  }
  $staleStock1 = $newStaleStock1
  $staleStock2 = $newStaleStock2

  $stockAfterProdNorm = Normalize-Stock $stock

  # เกณฑ์เตือนล่วงหน้า = 1.5 เท่าของ reorderThreshold (ขยับตามสัดส่วนวัตถุดิบแต่ละตัวเอง)
  # เป็นตัวเลขแสดงผลเท่านั้น ไม่กระทบ ReorderLayer()/reorderCost/state ใดๆ
  $nearDepletion = @{}
  foreach ($m in $threshNorm.Keys) {
    if ($stockAfterProdNorm[$m] -ge $threshNorm[$m] -and $stockAfterProdNorm[$m] -lt ($threshNorm[$m] * 1.5)) {
      $nearDepletion[$m] = $stockAfterProdNorm[$m]
    }
  }

  $reorder = ReorderLayer $stock $stockMax @("egg") $reorderThreshold @{ egg = 30 }
  $refilledNorm = @{}
  foreach ($m in $reorder.refilled.Keys) {
    $refilledNorm[$m] = if ($m -eq "egg") { $reorder.refilled[$m] } else { $reorder.refilled[$m] * 1000 }
  }

  $opExpenses = OperatingExpenses $check.actualProduced $sales.sold $day
  $outputSales = OutputSales $cashStart $sales.revenue $reorder.reorderCost $opExpenses.opExpenseCost
  $cashEnd = $outputSales.cashEnd
  $cash = $cashEnd

  # (Patch Draft "N/p growth" ปลดล็อก 2026-08-14) — shopRating/loyalty/N milestone
  # ผลลัพธ์วันนี้จะไปมีผลกับ p/N ของ "วันถัดไป" เท่านั้น (lag 1 วัน เหมือน
  # AutoProductionOrder()) ตัวขับเคลื่อนคือ shopRating (พฤติกรรมลูกค้าจริงวันนี้)
  $stockOutWalkAway = $sales.walkedAway - $sales.walkAwayChanceHits
  $totalSoldToday = 0
  foreach ($it in $items) { $totalSoldToday += $sales.sold[$it] }
  $freshSoldToday = 0
  foreach ($it in $items) { $freshSoldToday += $sales.soldFresh[$it] }
  $freshRatio = if ($totalSoldToday -gt 0) { $freshSoldToday / $totalSoldToday } else { 0.5 }

  # (แก้ 2026-08-14 — ผู้เล่นสั่ง) เดิมคนที่เดินหนีเพราะของหมดทุกคนโดนตัดคะแนน
  # เท่ากันหมด (-2 คงที่/คน) ไม่สมจริง เปลี่ยนเป็นสุ่ม "นิสัย" ทีละคนแทน — บาง
  # คนช่างมัน (ไม่ลด), บางคนปกติ (-2), บางคนหัวร้อน (-4) — สัดส่วน 30/40/30
  # เลือกไว้ให้ค่าเฉลี่ยระยะยาวเท่าเดิม (0.3×0 + 0.4×2 + 0.3×4 = 2.0/คน) แต่
  # รายวันจะแกว่งได้ตามนิสัยลูกค้าที่สุ่มมาจริง ไม่ใช่ตัวเลขนิ่งตายตัวอีกต่อไป
  $angerPenalty = 0
  $chillCount = 0; $normalCount = 0; $angryCount = 0
  for ($i = 0; $i -lt $stockOutWalkAway; $i++) {
    $mood = Get-Random -Minimum 0 -Maximum 100
    if ($mood -lt 30) { $chillCount++ }             # "ช่างมัน ไม่เป็นไร ครั้งหน้าค่อยมาใหม่"
    elseif ($mood -lt 70) { $angerPenalty += 2; $normalCount++ } # ปกติ
    else { $angerPenalty += 4; $angryCount++ }       # หัวร้อน
  }

  $satisfactionDelta = (($freshRatio - 0.5) * 4) - $angerPenalty
  $shopRating = $shopRating + $satisfactionDelta
  $shopRating = $shopRating + ((50 - $shopRating) * 0.05) # mean reversion เบาๆ กลับเข้าใกล้ 50
  # (แก้บั๊ก 2026-08-14 — ผู้เล่นสั่ง) เดิมใช้ [Math]::Max(0, [Math]::Min(100, ...))
  # ด้วยเลข Int32 ทำให้ PowerShell เลือก overload ผิดแล้วปัดทศนิยมทิ้งทุกวันโดย
  # ไม่ตั้งใจ (mean reversion แทบไม่มีผลจริงเพราะโดนปัดก่อนสะสม) เปลี่ยนเป็น
  # 0.0/100.0 ให้ชัดเจนว่าต้องเป็น double
  $shopRating = [Math]::Max(0.0, [Math]::Min(100.0, $shopRating))

  $consecutiveGoodDays = if ($stockOutWalkAway -eq 0) { $consecutiveGoodDays + 1 } else { 0 }

  # N ไม่มี milestone และไม่มี clamp เทียมของตัวเองอีกต่อไป — ขยับต่อเนื่องตาม
  # shopRating ล้วนๆ ทุกวัน เหมือน p ทุกประการ (ตัวจำกัดตามธรรมชาติมาจาก
  # shopRating ที่คลัมป์ 0-100 อยู่แล้วด้านบน ไม่ใช่จาก N โดยตรง)
  $customerPoolN = [Math]::Round(30 + (($shopRating - 50) * 0.4))
  $loyaltyPool = [Math]::Min(20, $consecutiveGoodDays * 0.5)
  $customerVisitP = [Math]::Max(0.05, [Math]::Min(0.95, 0.35 + (($shopRating - 50) * 0.003) + ($loyaltyPool * 0.005)))

  # เก็บเฉพาะ field ที่รายงานใช้จริง — ตัวที่คำนวณย้อนกลับได้จาก field อื่น
  # (totalCost, eggNeeded/eggActual, stockFinal, weightPct) ไม่เก็บซ้ำให้ log บวม
  $report = @{
    day = $day
    cashStart = $cashStart
    productionOrder = $productionOrder
    stockBefore = $stockBeforeNorm
    needed = $check.needed
    ratios = $ratios
    minRatio = $check.minRatio
    actualProduced = $check.actualProduced
    eggWasteBaht = $check.eggWasteBaht
    unitCost = $prod.unitCost
    totalCostWithWaste = $prod.totalCostWithWaste
    customers = $customers
    custGen = $custGen
    sold = $sales.sold
    revenue = $sales.revenue
    walkedAway = $sales.walkedAway
    walkAwayChanceHits = $sales.walkAwayChanceHits
    customerLog = $sales.customerLog
    staleSold = @{ fresh=$sales.soldFresh; stale1=$sales.soldStale1; stale2=$sales.soldStale2 }
    bundlePromoActive = $bundlePromoActive
    promoAvailableToday = $promoAvailableToday
    promoPBonus = $promoPBonus
    marketFloorPerItem = $marketFloorPerItem
    bundleSoldCount = $sales.bundleSoldCount
    discardedToday = $discardedToday
    discardWasteBaht = $discardWasteBaht
    hypeItem = $hypeItem
    appealDecay = $appealDecay
    consecutiveDays = $consecutiveDays
    stockAfterProduction = $stockAfterProdNorm
    threshold = $threshNorm
    nearDepletion = $nearDepletion
    refilled = $refilledNorm
    refilledCost = $reorder.refilledCost
    reorderCost = $reorder.reorderCost
    waterElecBase = $opExpenses.waterElecBase
    ovenElecCost = $opExpenses.ovenElecCost
    packagingCost = $opExpenses.packagingCost
    opExpenseCost = $opExpenses.opExpenseCost
    rentCost = $opExpenses.rentCost
    cashEnd = $cashEnd
    shopRating = $shopRating
    loyaltyPool = $loyaltyPool
    consecutiveGoodDays = $consecutiveGoodDays
    customerPoolN = $customerPoolN
    customerVisitP = $customerVisitP
    walkAwayMood = @{ chill = $chillCount; normal = $normalCount; angry = $angryCount }
  }
  $dayReports += $report

  Write-Host "Day $day computed. Customers=$customers Produced=$($check.actualProduced.shokupan)/$($check.actualProduced.melonpan)/$($check.actualProduced.anpan) Sold=$($sales.sold.shokupan)/$($sales.sold.melonpan)/$($sales.sold.anpan) CashEnd=$($cashEnd.ToString('N2'))"

  $prevOrder = $productionOrder
  $producedLast = $check.actualProduced
  $soldLast = $sales.sold
  $oldStockSoldLast = @{}
  foreach ($it in $items) { $oldStockSoldLast[$it] = $sales.soldStale1[$it] + $sales.soldStale2[$it] }

  # ต่อประวัติย้อนหลังของวันนี้เข้าไป เก็บแค่ 3 วันล่าสุด (ตัดวันเก่าสุดทิ้งถ้าเกิน)
  # ต้องบังคับ @() ทั้งสองฝั่งแยกกันก่อนบวก ไม่งั้นถ้า producedHist[$it] เพิ่งโดน
  # ConvertTo-Json ตอนมีสมาชิกตัวเดียวจะเหลือเป็น scalar (ไม่ใช่ array) ทำให้
  # `+` กลายเป็นการบวกเลขจริงๆ แทนการต่อ array (บั๊กที่เจอตอนทดสอบ Day146 —
  # ประวัติกลายเป็นผลรวมตัวเดียวแทนที่จะเป็น array หลายค่า)
  foreach ($it in $items) {
    $producedHist[$it] = @(@($producedHist[$it]) + @($producedLast[$it])) | Select-Object -Last 3
    $soldHist[$it] = @(@($soldHist[$it]) + @($soldLast[$it])) | Select-Object -Last 3
    $oldStockSoldHist[$it] = @(@($oldStockSoldHist[$it]) + @($oldStockSoldLast[$it])) | Select-Object -Last 3
    $orderedHist[$it] = @(@($orderedHist[$it]) + @($prevOrder[$it])) | Select-Object -Last 3
  }
}

$dayReports | ConvertTo-Json -Depth 6 | Set-Content -Path $ReportPath -Encoding utf8

# สะสม log รายวันแบบไม่ overwrite ของเก่า (ต่างจาก sim_report.json ที่มีแค่รอบล่าสุด)
# ใช้เพื่อย้อนดูแพทเทิร์นข้ามหลายวันตอนวิเคราะห์บัค/เสนอไอเดีย
# หมายเหตุ: ห้ามใช้ @($existingLog) + @($dayReports) ตรงๆ — ConvertFrom-Json บน
# array ที่ซับซ้อนบางกรณีคืนค่าที่ @()/+  ไม่ flatten ให้ ทำให้ได้ array ซ้อน
# array (เจอ bug นี้มาแล้วรอบหนึ่ง) ใช้ foreach เติมทีละตัวแทนเพื่อการันตี flat
$combinedLog = New-Object System.Collections.ArrayList
if (Test-Path $LogPath) {
  $existingLog = Get-Content $LogPath -Raw | ConvertFrom-Json
  foreach ($e in $existingLog) { [void]$combinedLog.Add($e) }
}
foreach ($r in $dayReports) { [void]$combinedLog.Add($r) }
$combinedLog | ConvertTo-Json -Depth 6 | Set-Content -Path $LogPath -Encoding utf8

$state = @{ stock=$stock; cash=$cash; history=$history; walkedAwayHistory=$walkedAwayHistory; lastDay=$TargetDay; prevOrder=$prevOrder; producedLast=$producedLast; soldLast=$soldLast; consecutiveDays=$consecutiveDays; staleStock1=$staleStock1; staleStock2=$staleStock2; shopRating=$shopRating; consecutiveGoodDays=$consecutiveGoodDays; oldStockSoldLast=$oldStockSoldLast; producedHist=$producedHist; soldHist=$soldHist; oldStockSoldHist=$oldStockSoldHist; orderedHist=$orderedHist }
$state | ConvertTo-Json | Set-Content -Path $StatePath -Encoding utf8

