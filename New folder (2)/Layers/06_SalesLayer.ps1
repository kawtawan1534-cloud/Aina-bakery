# ราคาของเก่าลดจากราคาเต็ม (stale1 -20%, stale2 -25%) — ใช้ทั้งคำนวณ weight
# (ผ่านสูตร weight=1/price^k เดิม ราคาลดจึงดันน้ำหนักโอกาสถูกเลือกขึ้นเอง
# โดยอัตโนมัติ ไม่ต้องเขียนสูตร selection ใหม่) และคำนวณ revenue จริง
# (Patch 6.5.1 แก้บัค: stale2 เดิมลด 50% ทำให้ขายต่ำกว่าต้นทุนทุกเมนู — ทั้ง
# 35/15=0.5 baht "Anpan" 30/15=0.5 "Shokupan" และหนักสุดที่ Melonpan
# 38*0.5=19 < unitCost 25.39 ขาดทุนทุกครั้งที่ขายได้ — ปรับเป็น -25% (mult 0.75)
# เพื่อให้ยังกำไรแม้บวกส่วนลดโปรซื้อคู่ซ้อนอีกชั้น ดู Patch_Log.txt)
# โปร "ซื้อคู่คุ้มกว่า" ($bundlePromoActive — Patch 6.5.1 เปิดถาวรทุกวันแล้ว
# ไม่ใช่สุ่มทั้งวันแบบเดิม): ลูกค้าบางส่วนซื้อของใหม่ 1 + ของเก่า 1 พร้อมกัน
# ได้ลดเพิ่มอีก 10% จากราคาที่ลดแล้ว ต่างจากลูกค้าปกติที่ซื้อได้แค่รายการเดียว
function SalesLayer($customers, $availableStock, $staleStock1, $staleStock2, $hypeItem, $appealDecay, $walkAwayChance, $bundlePromoActive) {
  $stalePriceMult = @{ fresh = 1.0; stale1 = 0.8; stale2 = 0.75 }
  $bundleExtraDiscount = 0.9   # ซื้อคู่คุ้มกว่า: ลดเพิ่มอีก 10% จากราคารวมที่ลดแล้ว
  $bundleAttemptChance = 0.2   # (Patch 6.5.1) โอกาสที่ลูกค้าแต่ละคนสนใจซื้อคู่
                               # จริงๆ — เดิมคือ 0.5 แต่ตอนนั้นยังมีเงื่อนไข
                               # "ต้องเป็นวันที่โปรเปิด" (10%/วัน) มาคูณซ้ำอีกชั้น
                               # ทำให้อัตราเฉลี่ยจริงต่ำกว่านี้มาก ตอนนี้โปรเปิด
                               # ทุกวันแล้ว จึงลดค่านี้ลงให้ยังสมเหตุสมผล

  $sold = @{}
  $soldFresh = @{}
  $soldStale1 = @{}
  $soldStale2 = @{}
  foreach ($item in $availableStock.Keys) {
    $sold[$item] = 0
    $soldFresh[$item] = 0
    $soldStale1[$item] = 0
    $soldStale2[$item] = 0
  }
  $walkedAway = 0
  $walkAwayChanceHits = 0
  $customerLog = @()
  $bundleSoldCount = 0
  $revenue = 0.0

  # เลือก pool ตัวเดียวด้วย weighted lottery (สูตรเดิมของระบบ) — คืน $null
  # ถ้าไม่มี pool ให้เลือกเลย ใช้ทั้งตอนซื้อเดี่ยวและตอนเลือกฝั่งใดฝั่งหนึ่งของคู่
  function Pick-WeightedPool($candidatePools) {
    if ($candidatePools.Count -eq 0) { return $null }
    $weights = $candidatePools | ForEach-Object {
      $effPrice = $prices[$_.item] * $stalePriceMult[$_.pool]
      $w = 1 / [Math]::Pow($effPrice, $k)
      if ($_.item -eq $hypeItem) { $w *= 1.5 }
      $decay = if ($appealDecay.ContainsKey($_.item)) { $appealDecay[$_.item] } else { 1.0 }
      $w * $decay * $_.mult
    }
    $sumWeights = ($weights | Measure-Object -Sum).Sum
    $r = (Get-Random -Minimum 0.0 -Maximum 1.0) * $sumWeights
    $choice = $candidatePools[$candidatePools.Count - 1]
    for ($i = 0; $i -lt $candidatePools.Count; $i++) {
      $r -= $weights[$i]
      if ($r -le 0) { $choice = $candidatePools[$i]; break }
    }
    return $choice
  }

  for ($c = 0; $c -lt $customers; $c++) {
    if ((Get-Random -Minimum 0.0 -Maximum 1.0) -lt $walkAwayChance) { $walkedAway++; $walkAwayChanceHits++; $customerLog += @{ walkedAway = $true }; continue }

    $freshPools = @()
    $stalePools = @()
    foreach ($item in $availableStock.Keys) {
      if ($availableStock[$item] -gt 0) { $freshPools += @{ item=$item; pool='fresh'; mult=1.0 } }
      if ($staleStock1.ContainsKey($item) -and $staleStock1[$item] -gt 0) { $stalePools += @{ item=$item; pool='stale1'; mult=0.5 } }
      if ($staleStock2.ContainsKey($item) -and $staleStock2[$item] -gt 0) { $stalePools += @{ item=$item; pool='stale2'; mult=0.2 } }
    }
    $pools = @($freshPools + $stalePools)
    if ($pools.Count -eq 0) { $walkedAway++; $customerLog += @{ walkedAway = $true }; continue }

    $tryBundle = $bundlePromoActive -and $freshPools.Count -gt 0 -and $stalePools.Count -gt 0 -and ((Get-Random -Minimum 0.0 -Maximum 1.0) -lt $bundleAttemptChance)

    if ($tryBundle) {
      $freshChoice = Pick-WeightedPool $freshPools
      $staleChoice = Pick-WeightedPool $stalePools

      $availableStock[$freshChoice.item] -= 1
      $sold[$freshChoice.item] += 1
      $soldFresh[$freshChoice.item] += 1

      $staleStockRef = if ($staleChoice.pool -eq 'stale1') { $staleStock1 } else { $staleStock2 }
      $staleStockRef[$staleChoice.item] -= 1
      $sold[$staleChoice.item] += 1
      if ($staleChoice.pool -eq 'stale1') { $soldStale1[$staleChoice.item] += 1 } else { $soldStale2[$staleChoice.item] += 1 }

      $bundlePrice = ($prices[$freshChoice.item] * $stalePriceMult.fresh + $prices[$staleChoice.item] * $stalePriceMult[$staleChoice.pool]) * $bundleExtraDiscount
      $revenue += $bundlePrice
      $bundleSoldCount++
      $customerLog += @{ bundle = $true; freshItem = $freshChoice.item; staleItem = $staleChoice.item; stalePool = $staleChoice.pool }
      continue
    }

    $choice = Pick-WeightedPool $pools

    $stockRef = switch ($choice.pool) {
      'fresh'  { $availableStock }
      'stale1' { $staleStock1 }
      'stale2' { $staleStock2 }
    }

    $roll = Get-Random -Minimum 0.0 -Maximum 1.0
    $wantQty = if ($roll -lt 0.7) { 1 } elseif ($roll -lt 0.9) { 2 } else { 3 }
    $actualQty = [Math]::Min($wantQty, $stockRef[$choice.item])

    $stockRef[$choice.item] -= $actualQty
    $sold[$choice.item] += $actualQty
    switch ($choice.pool) {
      'fresh'  { $soldFresh[$choice.item]  += $actualQty }
      'stale1' { $soldStale1[$choice.item] += $actualQty }
      'stale2' { $soldStale2[$choice.item] += $actualQty }
    }
    $revenue += $actualQty * $prices[$choice.item] * $stalePriceMult[$choice.pool]
    $customerLog += @{ item = $choice.item; qty = $actualQty; pool = $choice.pool }
  }

  return @{ sold=$sold; soldFresh=$soldFresh; soldStale1=$soldStale1; soldStale2=$soldStale2; walkedAway=$walkedAway; revenue=$revenue; walkAwayChanceHits=$walkAwayChanceHits; customerLog=$customerLog; bundleSoldCount=$bundleSoldCount }
}
