# Smart Contract pro Staking s Progresivním Úročením

## 1. Přehled projektu

### Účel
Smart contract pro staking ERC20 tokenů s progresivním úročením založeným na délce stakingu.

### Klíčové vlastnosti
- **Progresivní úročení** - čím déle stakuješ, tím vyšší APY
- **Automatický compound** - úroky se počítají s compoundem přes všechny tiery
- **Flexibilní claim** - uživatel si vybere, kdy chce vybrat rewards
- **3měsíční výpovědní lhůta** - ochrana likvidity projektu
- **Founder mód** - speciální režim bez úroků pro zakladatele
- **Emergency shutdown** - bezpečnostní mechanismus pro krizové situace

## 2. Tier systém (úrokové sazby)

| Tier | Období | APY | Popis |
|------|--------|-----|-------|
| 1 | 0-6 měsíců | 0.5% | Vstupní období |
| 2 | 6-12 měsíců | 0.7% | Základní tier |
| 3 | 12-24 měsíců | 2.0% | Pokročilý tier |
| 4 | 24-36 měsíců | 4.0% | Věrnostní tier |
| 5 | 36-48 měsíců | 5.0% | Premium tier |
| 6 | 48+ měsíců | 6.0% | VIP tier (neomezeno) |

### Příklad výpočtu
Uživatel stakuje 10,000 tokenů na 24 měsíců:
- **Tier 1** (0-6 měsíců): 10,000 × 0.5% × 0.5 = 25 tokenů
- **Tier 2** (6-12 měsíců): 10,025 × 0.7% × 0.5 = 35.09 tokenů
- **Tier 3** (12-24 měsíců): 10,060.09 × 2.0% × 1 = 201.2 tokenů
- **Celkem po 24 měsících**: ~10,261.3 tokenů

## 3. Architektura řešení

### Samostatné stake pozice
Každé přidání tokenů vytvoří samostatnou stake pozici s vlastním časovým záznamem.

**Klíčové vlastnosti:**
- Každý stake = samostatná pozice v array
- Samostatný výpočet rewards pro každou pozici s automatickým compoundem
- Uživatel vidí všechny své stake pozice jako seznam transakcí
- Flexibilní claim - uživatel si vybere, kdy chce vybrat rewards
- Žádné slučování = eliminace rizika bugů ve weighted average
- Transparentní - každá pozice má jasné datum a výši úroku

### Data struktura

```solidity
struct StakePosition {
    uint256 stakeId;           // Unikátní ID pozice (neměnné)
    uint256 amount;            // Množství tokenů
    uint256 startTime;         // Čas zahájení stakingu
    uint256 lastClaimTime;     // Poslední claim rewards
}

mapping(address => StakePosition[]) public userStakes;
mapping(address => bool) private isFounder;
uint256 public nextStakeId = 1;
mapping(address => mapping(uint256 => uint256)) private stakeIdToIndex;
```

## 4. Funkční požadavky

### 4.1 Core Contract funkce

| Funkce | Popis | Přístup |
|--------|-------|---------|
| `stake(uint256 amount)` | Vytvoření nové stake pozice | User |
| `claimRewards(uint256 stakeId)` | Výběr rewards z konkrétní pozice | User |
| `claimAllRewards()` | Výběr rewards ze všech pozic najednou | User |
| `requestWithdraw(uint256 stakeId, uint256 amount)` | Podání výpovědi pro pozici | User |
| `executeWithdraw(uint256 stakeId)` | Výběr po 3 měsících | User |
| `emergencyWithdraw()` | Výběr všech pozic při emergency shutdown | User |
| `cancelWithdrawRequest(uint256 stakeId)` | Zrušení nevyřízené výpovědi | User |

### 4.2 View funkce (read-only, gas free)

| Funkce | Popis |
|--------|-------|
| `getStakeInfo(address user)` | Kompletní info o všech stake pozicích |
| `getStakeByStakeId(address user, uint256 stakeId)` | Detail konkrétní pozice |
| `calculateRewards(address user, uint256 stakeId)` | Rewards pro konkrétní pozici |
| `calculateTotalRewards(address user)` | Součet rewards ze všech pozic |
| `getWithdrawableAmount(address user, uint256 stakeId)` | Kolik lze vybrat z pozice |
| `getPendingWithdrawals(address user)` | Všechny výpovědi (včetně provedených - pro historii) |
| `getActivePendingWithdrawals(address user)` | Pouze aktivní (neprovedené) výpovědi |
| `getCurrentTier(address user, uint256 stakeId)` | Aktuální tier konkrétní pozice |
| `getUserStakeCount(address user)` | Počet aktivních pozic uživatele |

### 4.3 Admin funkce

| Funkce | Popis | Oprávnění |
|--------|-------|-----------|
| `emergencyShutdown()` | Zahájení emergency módu | DEFAULT_ADMIN_ROLE |
| `grantRole(bytes32 role, address account)` | Přidělení role | DEFAULT_ADMIN_ROLE |
| `revokeRole(bytes32 role, address account)` | Odebrání role | DEFAULT_ADMIN_ROLE |
| `pause() / unpause()` | Pozastavení contractu | ADMIN_ROLE |
| `updateTierRates(uint256[] rates)` | Úprava úrokových sazeb | DEFAULT_ADMIN_ROLE |
| `depositTreasury(uint256 amount)` | Vložení tokenů do treasury | DEFAULT_ADMIN_ROLE |
| `withdrawTreasury(uint256 amount)` | Výběr nevyužitých tokenů z treasury | DEFAULT_ADMIN_ROLE |
| `getTreasuryBalance()` | Zobrazení zůstatku treasury | View |

## 5. Technická implementace

### 5.1 Stake mechanismus

```solidity
function stake(uint256 amount) external {
    uint256 stakeId = nextStakeId++;
    
    StakePosition memory newStake = StakePosition({
        stakeId: stakeId,
        amount: amount,
        startTime: block.timestamp,
        lastClaimTime: block.timestamp
    });
    
    userStakes[msg.sender].push(newStake);
    uint256 positionIndex = userStakes[msg.sender].length - 1;
    stakeIdToIndex[msg.sender][stakeId] = positionIndex;
    
    emit Staked(msg.sender, stakeId, amount, block.timestamp);
}
```

### 5.2 Withdrawal mechanismus

**3měsíční výpovědní lhůta:**
1. `requestWithdraw(stakeId, amount)` - zahájí 90denní odpočet
2. Po 90 dnech: `executeWithdraw(stakeId)` - skutečný výběr tokenů
3. Během výpovědní lhůty: rewards se stále počítají

#### Poznámky k provozu (custody / Web2 integrace)

- **Limit pending výpovědí:** Každá adresa může mít najednou maximálně `MAX_PENDING_WITHDRAWALS` aktivních (neprovedených) výpovědí.
- **Custody škálování:** Pokud držíte stake pozice mnoha koncových uživatelů pod jednou on-chain adresou (např. Web2 custody účet), výběry mohou být omezeny tímto limitem.
- **Doporučený postup:** Použijte více custody adres (batching/sharding) a stake pozice mezi nimi přesouvejte pomocí `adminTransferStake(from, stakeId, to)` ještě před vytvořením výpovědi.
- **Důležité:** `adminTransferStake` neumí přesunout pozici, která už má aktivní výpověď.

```solidity
struct WithdrawRequest {
    uint256 stakeId;
    uint256 amount;
    uint256 requestTime;
    uint256 availableAt;    // requestTime + 90 days
    bool executed;
}
```

### 5.3 Rewards mechanismus

**Automatický compound:**
- Úroky se počítají automaticky s compoundem při každém dotazu (VIEW funkce)
- Matematicky se rewards akumulují průběžně přes všechny tiery
- ŽÁDNÉ transakce nejsou pro výpočet potřeba

**Claim rewards:**
- `claimRewards(positionIndex)` - vybere rewards z konkrétní pozice
- `claimAllRewards()` - vybere rewards ze všech pozic najednou
- Po claimu se `position.amount` nezvyšuje - rewards jdou na wallet
- `position.lastClaimTime` se aktualizuje

### 5.4 Treasury management

Contract má separátní treasury fond pro výplatu rewards. Treasury musí být naplněn tokeny předem.

```solidity
uint256 public treasuryBalance;
uint256 public totalRewardsAllocated;

function depositTreasury(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    token.transferFrom(msg.sender, address(this), amount);
    treasuryBalance += amount;
    emit TreasuryDeposited(msg.sender, amount, block.timestamp);
}
```

**Důležité aspekty:**
- ✅ Oddělený účet pro rewards vs. stakované tokeny uživatelů
- ✅ Admin (DEFAULT_ADMIN_ROLE) musí udržovat treasury dostatečně naplněný
- ✅ View funkce `getTreasuryBalance()` pro monitoring stavu
- ⚠️ Pokud treasury dojde, rewards se nepřičítají

### 5.5 Security features

```solidity
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
```

- **ReentrancyGuard**: Ochrana proti reentrancy útokům
- **Pausable**: Možnost pozastavit contract v nouzi
- **AccessControl**: Role-based přístup (DEFAULT_ADMIN_ROLE, ADMIN_ROLE)
- **SafeERC20**: Bezpečná práce s ERC20 tokeny

**Role systém:**

```solidity
bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00; // Owner role
```

**DEFAULT_ADMIN_ROLE (úroveň Owner):**
- Přidělování/odebírání rolí
- Emergency shutdown
- Změna tier rates
- Správa treasury (deposit/withdraw)

**ADMIN_ROLE (úroveň Operátor):**
- Pause/Unpause contractu
- Monitoring operace

## 6. Events

```solidity
// User actions
event Staked(address indexed user, uint256 indexed stakeId, uint256 amount, uint256 timestamp);
event RewardsClaimed(address indexed user, uint256 indexed stakeId, uint256 rewardAmount, uint256 timestamp);
event AllRewardsClaimed(address indexed user, uint256 totalRewardAmount, uint256 timestamp);
event WithdrawRequested(address indexed user, uint256 indexed stakeId, uint256 amount, uint256 timestamp, uint256 availableAt);
event WithdrawExecuted(address indexed user, uint256 indexed stakeId, uint256 amount, uint256 timestamp);
event WithdrawCancelled(address indexed user, uint256 indexed stakeId, uint256 amount, uint256 timestamp);

// Admin actions
event EmergencyShutdown(address indexed admin, uint256 timestamp, uint256 totalStaked, uint256 totalRewards);
event ContractPaused(address indexed admin, uint256 timestamp);
event ContractUnpaused(address indexed admin, uint256 timestamp);
event TierRatesUpdated(address indexed admin, uint256[] newRates, uint256 timestamp);
event TreasuryDeposited(address indexed from, uint256 amount, uint256 timestamp);
event TreasuryWithdrawn(address indexed to, uint256 amount, uint256 timestamp);

// Role management
event AdminRoleGranted(address indexed account, address indexed grantor, uint256 timestamp);
event AdminRoleRevoked(address indexed account, address indexed revoker, uint256 timestamp);
```

## 7. Gas optimalizace

| Operace | 1 pozice | 50 pozic | Poznámka |
|---------|----------|----------|----------|
| `stake()` | ~50-60k gas | Stejné | Přidává vždy jen 1 pozici |
| `calculateTotalRewards()` | ~30-50k gas | ~500k gas | VIEW - zadarmo |
| `claimRewards(i)` | ~60-70k gas | Stejné | Claim 1 pozice |
| `claimAllRewards()` | ~70-80k gas | ~600k gas | Batch claim |
| `requestWithdraw(i)` | ~60k gas | Stejné | Withdrawal 1 pozice |

**Mitigace strategie:**
- View funkce off-chain (gratis)
- Volitelná merge funkce pro budoucnost
- Gas refundy při cleanup

## 8. Frontend optimalizace

```javascript
// ❌ ŠPATNĚ: 50 samostatných volání
for (let i = 0; i < 50; i++) {
  await contract.getStakePosition(user, i);
}

// ✅ DOBŘE: Jedno volání na všechny pozice
const allPositions = await contract.getStakeInfo(user);
```

**View funkce jsou zadarmo:**
- `getStakeInfo()` vrátí všechny pozice najednou
- `calculateTotalRewards()` agreguje off-chain
- Frontend může cachovat a zobrazovat okamžitě

## 9. Founder mód

Speciální režim pro zakladatele projektu:
- Hardcoded adresy při deployi
- Žádné úroky (APY = 0%)
- Standardní 3měsíční výpovědní lhůta
- Automatická detekce: founders bez úroků, veřejnost s úroky
