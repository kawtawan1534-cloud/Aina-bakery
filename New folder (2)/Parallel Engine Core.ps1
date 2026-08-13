# ===== Parallel Engine Core — Version: 6.5.1 =====
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
}

$customerPoolN = 30    # จำนวนคนสมมติในละแวกที่มีโอกาสแวะร้าน (จุดเกาะปัจจัยขนาดตลาดในอนาคต)
$customerVisitP = 0.35 # โอกาสที่แต่ละคนจะแวะวันนี้ (จุดเกาะปัจจัยความน่าดึงดูดรายวัน/ระยะยาวในอนาคต)
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

  $productionOrder = AutoProductionOrder $prevOrder $producedLast $soldLast $items

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

  $custGen = GenerateDailyCustomers $customerPoolN $customerVisitP
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
  }
  $dayReports += $report

  Write-Host "Day $day computed. Customers=$customers Produced=$($check.actualProduced.shokupan)/$($check.actualProduced.melonpan)/$($check.actualProduced.anpan) Sold=$($sales.sold.shokupan)/$($sales.sold.melonpan)/$($sales.sold.anpan) CashEnd=$($cashEnd.ToString('N2'))"

  $prevOrder = $productionOrder
  $producedLast = $check.actualProduced
  $soldLast = $sales.sold
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

$state = @{ stock=$stock; cash=$cash; history=$history; walkedAwayHistory=$walkedAwayHistory; lastDay=$TargetDay; prevOrder=$prevOrder; producedLast=$producedLast; soldLast=$soldLast; consecutiveDays=$consecutiveDays; staleStock1=$staleStock1; staleStock2=$staleStock2 }
$state | ConvertTo-Json | Set-Content -Path $StatePath -Encoding utf8

