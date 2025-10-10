# Quick Guide: Create-DailyFocus.ps1

## 🎯 Призначення
Скрипт автоматично створює та оновлює щоденні файли **Dashboard**, **Timeline** та **RestoreLog** у модулі `C06_FOCUS`.  
Також підтримує реєстрацію завдань (ранок / вечір) у планувальнику Windows.

---

## 🔑 Основні команди

### 1. Одноразовий запуск
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "D:\CHECHA_CORE\C06_FOCUS\Create-DailyFocus.ps1" `
  -Root "D:\CHECHA_CORE\C06_FOCUS" -UpdateStatus
```
Результат:
- `FOCUS_Dashboard.md`
- `FOCUS_RestoreLog.md`
- `FOCUS_Timeline.md`

---

### 2. Отримати об’єкт у змінну `$res`
> Викликати через `&` (не через `-File`), щоб результат зберігався у твоїй сесії.

```powershell
$res = & "D:\CHECHA_CORE\C06_FOCUS\Create-DailyFocus.ps1" `
  -Root "D:\CHECHA_CORE\C06_FOCUS" -UpdateStatus -PassThru

$res.Dashboard
$res.RestoreLog
$res.Timeline
```

---

### 3. Dot-sourcing (завантаження функцій прямо у сесію)
```powershell
. "D:\CHECHA_CORE\C06_FOCUS\Create-DailyFocus.ps1" -Root "D:\CHECHA_CORE\C06_FOCUS" -UpdateStatus -PassThru
```

---

### 4. Реєстрація задач (адмін-права)
```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "D:\CHECHA_CORE\C06_FOCUS\Create-DailyFocus.ps1" `
  -Root "D:\CHECHA_CORE\C06_FOCUS" -RegisterTasks
```

Зареєструються:
- **CheCha-Focus-Morning** (07:30) → генерує Dashboard/Timeline
- **CheCha-Focus-Evening** (21:30) → оновлює RestoreLog

---

## 📂 Результат роботи
- `FOCUS_Dashboard.md` → щоденний фокус
- `FOCUS_Timeline.md` → таймлайн подій дня
- `FOCUS_RestoreLog.md` → вечірній журнал відновлення
- `FOCUS_Status.json` → технічний стан для інтеграції

---

## 🛠 Рекомендації
- Використовуй `-PassThru`, якщо треба обробляти результати в інших скриптах.  
- Можеш інтегрувати вечірній запуск із `git commit` для щоденних збережень.  
- Наступний рівень — підключити дані з `MAT_RESTORE.csv` у RestoreLog.  

---

📌 Автор: С.Ч.  
Версія: Quick Guide v1.0  
