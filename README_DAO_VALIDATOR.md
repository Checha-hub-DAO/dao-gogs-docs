# Інтеграція DAO-VALIDATOR з GitBook

## 🔧 Інструкція

### 1. Створення GitHub-репозиторію
- Назва: `dao-gogs-docs`
- Додайте туди структуру:
  ```
  dao-validator/
    └── scripts/validate_structure.py
    └── requirements.txt
  DAO-G01/
    └── SUMMARY.md
    └── README.md
  ```

### 2. Додайте GitHub Actions workflow

```yaml
name: Validate DAO Modules

on:
  push:
    paths:
      - 'DAO-G*/**.md'
  workflow_dispatch:

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.10'
      - name: Install dependencies
        run: pip install -r dao-validator/requirements.txt
      - name: Run DAO Validator
        run: python dao-validator/scripts/validate_structure.py
```

### 3. Налаштуйте GitBook Git Sync
- У GitBook → ⚙️ → Git Sync
- Підключіть ваш GitHub репозиторій
- Оберіть `main` гілку
- Активуйте односторонню або двосторонню синхронізацію

## ✅ Результат

- Перевірка структури DAO при кожному push
- Генерація файлу `validation_report.md`
- Стандартизована документація