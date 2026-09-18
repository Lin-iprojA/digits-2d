import os
import json
import re
import asyncio
import urllib.request
from datetime import datetime, timedelta, timezone
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import List, Optional

app = FastAPI(title="2D Lottery Probability & Payout Engine")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- TELEGRAM BOT CONFIG ---
TELEGRAM_BOT_TOKEN = "8722201597:AAEkc0KnvT2xkate4wF2rKkkKizadb2w-4g"
TELEGRAM_API_URL = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}"

user_states = {}
pending_confirmations = {}  # Store bets waiting for user confirmation
active_chats = set()

# --- TIME & SESSION HELPERS (MYANMAR TIMEZONE UTC+6:30) ---
ARCHIVE_DIR = "archives"
os.makedirs(ARCHIVE_DIR, exist_ok=True)

MYANMAR_TO_ENG_DIGITS = str.maketrans("၀၁၂၃၄၅၆၇၈၉", "0123456789")

def get_myanmar_time():
    utc_now = datetime.now(timezone.utc)
    mm_now = utc_now + timedelta(hours=6, minutes=30)
    return mm_now

def get_current_session():
    now = get_myanmar_time()
    # 2D Session Schedule Rules:
    # 1. Evening Session: From 12:01:00 PM up to 04:30:00 PM today.
    # 2. Morning Session: From 04:30:01 PM today up to 12:00:59 PM next day.
    if now.hour == 12 and now.minute >= 1:
        return "Evening (04:30 PM)"
    elif 13 <= now.hour < 16:
        return "Evening (04:30 PM)"
    elif now.hour == 16 and now.minute <= 30:
        return "Evening (04:30 PM)"
    else:
        return "Morning (12:01 PM)"

def format_session_burmese(session_name: str) -> str:
    if "Morning" in session_name:
        return "မနက်ပိုင်း (၁၂:၀၁) ပွဲ"
    else:
        return "ညနေပိုင်း (၄:၃၀) ပွဲ"

def format_time_burmese(dt: datetime) -> str:
    date_str = dt.strftime("%Y-%m-%d")
    period = "မနက်" if dt.hour < 12 else "ညနေ"
    time_str = dt.strftime("%I:%M:%S")
    return f"{date_str} ({period} {time_str})"

def format_num_amount(amt: float) -> str:
    if amt.is_integer():
        return f"{int(amt):,}"
    return f"{amt:,.2f}"

def archive_session_records(session_name: str, bets_to_archive: List[dict]):
    if not bets_to_archive:
        return
    now_str = get_myanmar_time().strftime("%Y-%m-%d")
    safe_session = session_name.replace(" ", "_").replace(":", "-").replace("(", "").replace(")", "")
    filename = os.path.join(ARCHIVE_DIR, f"bets_{now_str}_{safe_session}.json")

    existing_data = []
    if os.path.exists(filename):
        try:
            with open(filename, "r", encoding="utf-8") as f:
                existing_data = json.load(f)
        except Exception:
            existing_data = []

    existing_data.extend(bets_to_archive)
    with open(filename, "w", encoding="utf-8") as f:
        json.dump(existing_data, f, indent=2, ensure_ascii=False)

def send_telegram_message(chat_id, text, reply_markup=None):
    url = f"{TELEGRAM_API_URL}/sendMessage"
    payload = {"chat_id": chat_id, "text": text}
    if reply_markup:
        payload["reply_markup"] = reply_markup
    try:
        req = urllib.request.Request(url, data=json.dumps(payload).encode('utf-8'), headers={'Content-Type': 'application/json'})
        urllib.request.urlopen(req)
    except Exception as e:
        print(f"Telegram API Error: {e}")

# --- ADVANCED BURMESE 2D FREE-TEXT PARSER ---
def parse_2d_text_input(raw_text: str) -> dict:
    text = raw_text.translate(MYANMAR_TO_ENG_DIGITS).strip()
    bets = []
    lines = [line.strip() for line in text.splitlines() if line.strip()]

    current_header = None

    for line in lines:
        if line.lower() in ["ဒဲ့", "straight"]:
            current_header = "straight"
            continue

        # 1. Check Break + Poo: "2ဘရိတ်ပူး 500" or "2ဘရိတ်ပူးပါ 500"
        m = re.search(r'^(\d)\s*(?:ဘရိတ်ပူးပါ|ဘရိတ်ပူး|break\s*poo)\s*=?\s*(\d+)$', line, re.IGNORECASE)
        if m:
            target_digit = int(m.group(1))
            amount = float(m.group(2))
            break_nums = sorted([f"{i}{(target_digit - i) % 10}" for i in range(10)])
            doubles = [n for n in break_nums if n[0] == n[1]]
            expanded = break_nums + doubles
            item_total = len(expanded) * amount

            bets.append({
                "bet_type": "ဘရိတ်ပူး",
                "input_value": str(target_digit),
                "expanded_numbers": break_nums,
                "amount_per_number": amount,
                "total_amount": item_total,
                "notes": f"Includes {len(doubles)} extra Poo doubles ({', '.join(doubles)})"
            })
            continue

        # 2. Check Break: "2ဘရိတ် 500"
        m = re.search(r'^(\d)\s*(?:ဘရိတ်|break)\s*=?\s*(\d+)$', line, re.IGNORECASE)
        if m:
            target_digit = int(m.group(1))
            amount = float(m.group(2))
            break_nums = sorted([f"{i}{(target_digit - i) % 10}" for i in range(10)])
            item_total = len(break_nums) * amount
            bets.append({
                "bet_type": "ဘရိတ်",
                "input_value": str(target_digit),
                "expanded_numbers": break_nums,
                "amount_per_number": amount,
                "total_amount": item_total
            })
            continue

        # 3. Check Pat Thee + Poo: "၁ပတ်သီးပူးပါ 250" or "1ပတ်သီးပူး 250"
        m = re.search(r'^(\d)\s*(?:ပတ်သီးပူးပါ|ပတ်သီးပူး|ပတ်ပူးပါ|ပတ်ပူး|pat\s*thee\s*poo)\s*=?\s*(\d+)$', line, re.IGNORECASE)
        if m:
            digit = m.group(1)
            amount = float(m.group(2))
            pat_thee = set()
            for i in range(10):
                pat_thee.add(f"{digit}{i}")
                pat_thee.add(f"{i}{digit}")
            pat_thee_nums = sorted(list(pat_thee))
            item_total = 20 * amount
            bets.append({
                "bet_type": "ပတ်သီးပူး",
                "input_value": digit,
                "expanded_numbers": pat_thee_nums,
                "amount_per_number": amount,
                "total_amount": item_total,
                "notes": f"Includes extra double ({digit}{digit})"
            })
            continue

        # 4. Check Pat Thee: "1/6ပတ်=250" or "1/6ပတ်သီး=250"
        m = re.search(r'^([\d/\-\,\s]+)\s*(?:ပတ်သီး|ပတ်|pat\s*thee|patthee|pat)\s*=?\s*(\d+)$', line, re.IGNORECASE)
        if m:
            raw_digits = m.group(1)
            amount = float(m.group(2))
            digits = re.findall(r'\d', raw_digits)
            all_expanded = []
            for d in digits:
                pat_thee = set()
                for i in range(10):
                    pat_thee.add(f"{d}{i}")
                    pat_thee.add(f"{i}{d}")
                all_expanded.extend(sorted(list(pat_thee)))
            item_total = len(all_expanded) * amount
            bets.append({
                "bet_type": "ပတ်သီး",
                "input_value": ", ".join(digits),
                "expanded_numbers": sorted(list(set(all_expanded))),
                "amount_per_number": amount,
                "total_amount": item_total
            })
            continue

        # 5. Check Kway Poo: "2716ခွေပူး5000" or "1234ခွေပူး4000"
        m = re.search(r'^(\d{2,10})\s*(?:ခွေပူး|kway\s*poo|kwaypoo)\s*=?\s*(\d+)$', line, re.IGNORECASE)
        if m:
            digits_str = m.group(1)
            amount = float(m.group(2))
            raw_digits_list = re.findall(r'\d', digits_str)
            unique_digits = sorted(list(set(raw_digits_list)))
            expanded = set()
            for i in unique_digits:
                for j in unique_digits:
                    expanded.add(f"{i}{j}")
            exp_list = sorted(list(expanded))
            item_total = len(exp_list) * amount
            formatted_input = ", ".join(raw_digits_list)
            bets.append({
                "bet_type": "ခွေပူး",
                "input_value": formatted_input,
                "expanded_numbers": exp_list,
                "amount_per_number": amount,
                "total_amount": item_total
            })
            continue

        # 6. Check Kway: "2716ခွေ5000"
        m = re.search(r'^(\d{2,10})\s*(?:ခွေ|kway)\s*=?\s*(\d+)$', line, re.IGNORECASE)
        if m:
            digits_str = m.group(1)
            amount = float(m.group(2))
            raw_digits_list = re.findall(r'\d', digits_str)
            unique_digits = sorted(list(set(raw_digits_list)))
            expanded = set()
            for i in unique_digits:
                for j in unique_digits:
                    if i != j:
                        expanded.add(f"{i}{j}")
            exp_list = sorted(list(expanded))
            item_total = len(exp_list) * amount
            formatted_input = ", ".join(raw_digits_list)
            bets.append({
                "bet_type": "ခွေ",
                "input_value": formatted_input,
                "expanded_numbers": exp_list,
                "amount_per_number": amount,
                "total_amount": item_total
            })
            continue

        # 7. Check Numbers with Attached R (Return): "25-20-26-21-23-28r5000" or "75-70-76-71-73-78r5000"
        m = re.search(r'^([\d/\-\,\s]+?)(?:r|ရရ|ရ)\s*=?\s*(\d+)$', line, re.IGNORECASE)
        if m:
            raw_nums = m.group(1)
            amount = float(m.group(2))
            nums = re.findall(r'\b\d{2}\b', raw_nums)
            if nums:
                expanded = set()
                for num in nums:
                    expanded.add(num)
                    expanded.add(num[::-1])
                exp_list = sorted(list(expanded))
                item_total = len(exp_list) * amount
                bets.append({
                    "bet_type": "R",
                    "input_value": ", ".join(nums),
                    "expanded_numbers": exp_list,
                    "amount_per_number": amount,
                    "total_amount": item_total
                })
                continue

        # 8. Check Poo: "11/66=250" or "1ပူး 250" or "ပူး 250"
        m = re.search(r'^([\d/\-\,\s]*)\s*(?:ပူး|poo)\s*=?\s*(\d+)$', line, re.IGNORECASE)
        if m and m.group(2):
            raw_nums = m.group(1).strip()
            amount = float(m.group(2))
            nums = re.findall(r'\d+', raw_nums)
            expanded = set()
            if nums:
                for n in nums:
                    if len(n) == 2:
                        expanded.add(n)
                    elif len(n) == 1:
                        expanded.add(f"{n}{n}")
            else:
                for i in range(10):
                    expanded.add(f"{i}{i}")
            if expanded:
                exp_list = sorted(list(expanded))
                item_total = len(exp_list) * amount
                bets.append({
                    "bet_type": "ပူး",
                    "input_value": raw_nums if raw_nums else "အပူးအားလုံး",
                    "expanded_numbers": exp_list,
                    "amount_per_number": amount,
                    "total_amount": item_total
                })
                continue

        # 9. Single Line Numbers + Amount: "12- 500" or "34- 1000" or "17/12/10/14 300" or "70-50 1000"
        m = re.search(r'^([\d/\-\,\s]+?)\s*=?\s*(\d{2,7})$', line)
        if m:
            raw_nums = m.group(1)
            amount = float(m.group(2))
            nums = re.findall(r'\b\d{2}\b', raw_nums)
            if nums:
                item_total = len(nums) * amount
                bets.append({
                    "bet_type": "ဒဲ့",
                    "input_value": ", ".join(nums),
                    "expanded_numbers": sorted(list(set(nums))),
                    "amount_per_number": amount,
                    "total_amount": item_total
                })
                continue

    # Fallback if no line-pattern matched but numbers + trailing amount exist
    if not bets:
        amt_match = re.search(r'(\d{2,7})$', text)
        if amt_match:
            amount = float(amt_match.group(1))
            raw_nums_part = text[:amt_match.start()]
            nums = re.findall(r'\b\d{2}\b', raw_nums_part)
            if nums and amount > 0:
                item_total = len(nums) * amount
                bets.append({
                    "bet_type": "ဒဲ့",
                    "input_value": ", ".join(nums),
                    "expanded_numbers": sorted(list(set(nums))),
                    "amount_per_number": amount,
                    "total_amount": item_total
                })

    grand_total = sum(b["total_amount"] for b in bets)
    return {
        "items": bets,
        "grand_total": grand_total
    }

# In-memory storage for demonstration
bets_db = []
current_draw = {
    "winning_number": None,
    "status": "Waiting for draw",
    "session": get_current_session()
}

class BetCreate(BaseModel):
    customer_name: str
    bet_type: str
    input_value: str
    amount: float

class DrawUpdate(BaseModel):
    winning_number: str

def expand_numbers(bet_type: str, input_val: str) -> List[str]:
    bet_type_lower = bet_type.strip().lower()
    input_val = input_val.strip()

    expanded = set()

    if "straight" in bet_type_lower or "ဒဲ့" in bet_type_lower:
        if len(input_val) == 2 and input_val.isdigit():
            expanded.add(input_val)

    elif "return" in bet_type_lower or "r (" in bet_type_lower or bet_type_lower == "r":
        if len(input_val) == 2 and input_val.isdigit():
            expanded.add(input_val)
            expanded.add(input_val[::-1])

    elif bet_type_lower == "poo" or "ပူး" in bet_type_lower and "ခွေပူး" not in bet_type_lower:
        digits = [c for c in input_val if c.isdigit()]
        if digits:
            for d in set(digits):
                expanded.add(f"{d}{d}")
        else:
            for i in range(10):
                expanded.add(f"{i}{i}")

    elif "pat thee" in bet_type_lower or "patthee" in bet_type_lower or "ပတ်သီး" in bet_type_lower:
        if len(input_val) == 1 and input_val.isdigit():
            d = input_val
            for i in range(10):
                expanded.add(f"{d}{i}")
                expanded.add(f"{i}{d}")

    elif bet_type_lower == "kway poo" or "ခွေပူး" in bet_type_lower or bet_type_lower == "kway poo (ခွေပူး)":
        digits = [c for c in input_val if c.isdigit()]
        unique_digits = list(set(digits))
        if len(unique_digits) >= 2:
            for i in unique_digits:
                for j in unique_digits:
                    if i != j:
                        expanded.add(f"{i}{j}")
            for d in unique_digits:
                expanded.add(f"{d}{d}")

    elif "kway" in bet_type_lower or "ခွေ" in bet_type_lower:
        digits = [c for c in input_val if c.isdigit()]
        unique_digits = list(set(digits))
        if len(unique_digits) >= 2:
            for i in unique_digits:
                for j in unique_digits:
                    if i != j:
                        expanded.add(f"{i}{j}")

    elif "break" in bet_type_lower or "ဘရိတ်" in bet_type_lower:
        if input_val.isdigit():
            target_sum = int(input_val) % 10
            for i in range(10):
                for j in range(10):
                    if (i + j) % 10 == target_sum:
                        expanded.add(f"{i}{j}")

    return sorted(list(expanded))

@app.post("/api/bets")
def submit_bet(bet: BetCreate):
    parsed = parse_2d_text_input(bet.input_value if bet.bet_type == "Smart Text" else f"{bet.input_value} {bet.amount}")

    mm_now = get_myanmar_time()
    formatted_time = mm_now.strftime("%Y-%m-%d %I:%M:%S %p")
    time_bm = format_time_burmese(mm_now)
    session_name = get_current_session()

    if parsed["items"]:
        added_records = []
        for item in parsed["items"]:
            bet_id = len(bets_db) + 1
            win_status = "Pending"
            payout = 0.0

            winning_num = current_draw.get("winning_number")
            if winning_num and current_draw.get("session") == session_name:
                if winning_num in item["expanded_numbers"]:
                    win_status = "Win"
                    payout = item["amount_per_number"] * 80.0
                else:
                    win_status = "Lose"
                    payout = 0.0

            bet_record = {
                "id": bet_id,
                "customer_name": bet.customer_name,
                "bet_type": item["bet_type"],
                "input_value": item["input_value"],
                "expanded_numbers": item["expanded_numbers"],
                "amount_per_number": item["amount_per_number"],
                "total_amount": item["total_amount"],
                "win_status": win_status,
                "payout": payout,
                "session": session_name,
                "created_at": formatted_time,
                "created_at_bm": time_bm,
                "is_archived": False
            }
            bets_db.append(bet_record)
            added_records.append(bet_record)

        return {
            "message": "Bets submitted successfully",
            "bet": added_records[0],
            "records": added_records,
            "grand_total": parsed["grand_total"]
        }

    numbers = expand_numbers(bet.bet_type, bet.input_value)
    if not numbers:
        raise HTTPException(status_code=400, detail="Invalid input for the selected bet type.")

    bet_id = len(bets_db) + 1
    win_status = "Pending"
    payout = 0.0

    total_amount = bet.amount * len(numbers)

    winning_num = current_draw.get("winning_number")
    if winning_num and current_draw.get("session") == session_name:
        if winning_num in numbers:
            win_status = "Win"
            payout = bet.amount * 80.0
        else:
            win_status = "Lose"
            payout = 0.0

    bet_record = {
        "id": bet_id,
        "customer_name": bet.customer_name,
        "bet_type": bet.bet_type,
        "input_value": bet.input_value,
        "expanded_numbers": numbers,
        "amount_per_number": bet.amount,
        "total_amount": total_amount,
        "win_status": win_status,
        "payout": payout,
        "session": session_name,
        "created_at": formatted_time,
        "created_at_bm": time_bm,
        "is_archived": False
    }
    bets_db.append(bet_record)
    return {"message": "Bet submitted successfully", "bet": bet_record}

@app.get("/api/bets")
def get_bets(include_archived: bool = False):
    if include_archived:
        return {"bets": bets_db}
    else:
        active_bets = [b for b in bets_db if not b.get("is_archived", False)]
        return {"bets": active_bets, "session": get_current_session()}

@app.get("/api/archives")
def get_archives():
    files = []
    if os.path.exists(ARCHIVE_DIR):
        files = os.listdir(ARCHIVE_DIR)
    return {"archives": sorted(files, reverse=True)}

@app.get("/api/draw")
def get_draw():
    current_session = get_current_session()
    if current_draw.get("session") != current_session:
        current_draw["winning_number"] = None
        current_draw["status"] = "Waiting for draw"
        current_draw["session"] = current_session
    return current_draw

@app.post("/api/draw")
def set_draw(draw: DrawUpdate):
    winning_num = draw.winning_number.strip()
    if len(winning_num) != 2 or not winning_num.isdigit():
        raise HTTPException(status_code=400, detail="Winning number must be exactly 2 digits.")

    session_name = get_current_session()
    session_bm = format_session_burmese(session_name)
    current_draw["winning_number"] = winning_num
    current_draw["status"] = f"Drawn ({session_name})"
    current_draw["session"] = session_name

    # Broadcast Live Draw Result to Telegram
    for chat_id in active_chats:
        send_telegram_message(chat_id, f"📢 LIVE DRAW UPDATE ({session_bm})!\n\nThe winning 2D number is: 🎉 {winning_num} 🎉")

    settled_bets = []
    for bet in bets_db:
        if not bet.get("is_archived", False):
            if winning_num in bet["expanded_numbers"]:
                bet["win_status"] = "Win"
                bet["payout"] = bet["amount_per_number"] * 80.0
                chat_id = bet.get("chat_id")
                if chat_id:
                    send_telegram_message(
                        chat_id,
                        f"🎊 CONGRATULATIONS! 🎊\nYour bet on {bet['input_value']} ({bet['bet_type']}) won!\n\nPayout: {format_num_amount(bet['payout'])} MMK\nPlaced At: {bet.get('created_at_bm', bet['created_at'])}"
                    )
            else:
                bet["win_status"] = "Lose"
                bet["payout"] = 0.0
                chat_id = bet.get("chat_id")
                if chat_id:
                    send_telegram_message(
                        chat_id,
                        f"❌ Sorry, you lost your bet on {bet['input_value']} ({bet['bet_type']}).\nPlaced At: {bet.get('created_at_bm', bet['created_at'])}"
                    )

            bet["is_archived"] = True
            settled_bets.append(bet)

    archive_session_records(session_name, settled_bets)

    return {
        "message": f"Winning number set for {session_name}. Payouts calculated and session archived!",
        "draw": current_draw,
        "archived_count": len(settled_bets)
    }

# Helper to save pending confirmation bet into bets_db and send final voucher
def execute_bet_confirmation(chat_id, name):
    if chat_id not in pending_confirmations:
        send_telegram_message(chat_id, "⚠️ အတည်ပြုရန် စာရင်းမရှိပါ သို့မဟုတ် သက်တမ်းကုန်သွားပါပြီ။")
        return

    pending = pending_confirmations[chat_id]
    session_name = pending["session_name"]
    formatted_time = pending["formatted_time"]
    time_bm = pending["time_bm"]
    items = pending["items"]
    grand_total = pending["grand_total"]

    added_records = []
    for item in items:
        bet_id = len(bets_db) + 1
        bet_record = {
            "id": bet_id,
            "customer_name": f"TG_{name}",
            "chat_id": chat_id,
            "bet_type": item["bet_type"],
            "input_value": item["input_value"],
            "expanded_numbers": item["expanded_numbers"],
            "amount_per_number": item["amount_per_number"],
            "total_amount": item["total_amount"],
            "win_status": "Pending",
            "payout": 0.0,
            "session": session_name,
            "created_at": formatted_time,
            "created_at_bm": time_bm,
            "is_archived": False
        }
        bets_db.append(bet_record)
        added_records.append(bet_record)

    del pending_confirmations[chat_id]

    session_bm = format_session_burmese(session_name)

    # Send Final Voucher Exactly in requested Burmese format!
    if len(added_records) == 1:
        r = added_records[0]
        exp_count = len(r["expanded_numbers"])
        exp_str = ", ".join(r["expanded_numbers"])
        amt_str = format_num_amount(r["amount_per_number"])
        total_str = format_num_amount(r["total_amount"])

        voucher_str = (
            f"✅ ဘောက်ချာ ဖြတ်ပြီးပါပြီ!\n\n"
            f"ပွဲစဉ် - {session_bm}\n"
            f"ထိုးခဲ့တဲ့အချိန် - {time_bm}\n"
            f"ထိုးကွက် - {r['input_value']} ({r['bet_type']})\n"
            f"ဂဏန်း ({exp_count}) ကွက် - {exp_str}\n"
            f"တစ်ကွက် - {amt_str} ကျပ်\n"
            f"စုစုပေါင်း - {total_str} ကျပ်\n\n"
            f"ပေါက်ဂဏန်းထွက်မယ့်အချိန်ကို စောင့်ကြည့်လိုက်ရအောင်..."
            f"ထီပေါက်ပါစေ... Good Luck ပါ...🍀..."
        )
        send_telegram_message(chat_id, voucher_str)
    else:
        voucher_lines = [
            f"✅ ဘောက်ချာ ဖြတ်ပြီးပါပြီ!\n",
            f"ပွဲစဉ် - {session_bm}",
            f"ထိုးခဲ့တဲ့အချိန် - {time_bm}\n",
            "──────────────────────"
        ]
        for idx, r in enumerate(added_records, 1):
            exp_count = len(r["expanded_numbers"])
            exp_preview = ", ".join(r["expanded_numbers"][:15])
            if exp_count > 15:
                exp_preview += f"... (+{exp_count - 15} ကွက်)"
            amt_str = format_num_amount(r["amount_per_number"])
            item_tot_str = format_num_amount(r["total_amount"])

            line_str = (
                f"{idx}️⃣ ထိုးကွက် - {r['input_value']} ({r['bet_type']})\n"
                f"   ဂဏန်း ({exp_count}) ကွက် - {exp_preview}\n"
                f"   တစ်ကွက် - {amt_str} ကျပ်\n"
                f"   စုစုပေါင်း - {item_tot_str} ကျပ်"
            )
            voucher_lines.append(line_str)

        grand_tot_str = format_num_amount(grand_total)
        voucher_lines.append("──────────────────────")
        voucher_lines.append(f"💰 စုစုပေါင်း - {grand_tot_str} ကျပ်\n")
        voucher_lines.append("ပေါက်ဂဏန်းထွက်မယ့်အချိန်ကို စောင့်ကြည့်လိုက်ရအောင်...")

        send_telegram_message(chat_id, "\n".join(voucher_lines))

# --- TELEGRAM WEBHOOK / UPDATE PROCESSOR ---
@app.post("/webhook/telegram")
async def telegram_webhook(update: dict):
    if "message" in update and "text" in update["message"]:
        chat_id = update["message"]["chat"]["id"]
        text = update["message"]["text"].strip()
        name = update["message"]["from"].get("first_name", "User")
        active_chats.add(chat_id)

        session_name = get_current_session()

        # Handle /start or /bet
        if text.lower() in ["/start", "/bet", "bet", "start"]:
            send_telegram_message(
                chat_id,
                f"Hello {name}! 🎲 Welcome to 2D Lottery.\n"
                f"လက်ရှိပွဲစဉ် - {format_session_burmese(session_name)}\n\n"
                f"သင့်ထိုးလိုသော 2D ဂဏန်းများကို အောက်ပါအတိုင်း တိုက်ရိုက် စာရိုက်၍ ပို့ပေးပါ-\n\n"
                f"• 11/66=250\n"
                f"• 1/6ပတ်=250\n"
                f"• 2716ခွေပူး5000\n"
                f"• 25-20-26r5000\n"
                f"• 2ဘရိတ် 500"
            )
            return {"status": "ok"}

        # Handle text "confirm" or "confirmed"
        if text.lower() in ["confirm", "confirmed", "ok", "အတည်ပြုမည်"] and chat_id in pending_confirmations:
            execute_bet_confirmation(chat_id, name)
            return {"status": "ok"}

        # Handle text "cancel"
        if text.lower() in ["cancel", "မထိုးတော့ပါ", "ဖျက်မည်"] and chat_id in pending_confirmations:
            del pending_confirmations[chat_id]
            send_telegram_message(chat_id, "❌ ထိုးကြေးစာရင်းကို ဖျက်လိုက်ပါပြီ။")
            return {"status": "ok"}

        # Try parsing free text!
        parsed = parse_2d_text_input(text)
        if parsed["items"]:
            mm_now = get_myanmar_time()
            formatted_time = mm_now.strftime("%Y-%m-%d %I:%M:%S %p")
            time_bm = format_time_burmese(mm_now)
            session_bm = format_session_burmese(session_name)

            # Store in pending confirmations (DO NOT SAVE TO bets_db YET!)
            pending_confirmations[chat_id] = {
                "items": parsed["items"],
                "grand_total": parsed["grand_total"],
                "session_name": session_name,
                "formatted_time": formatted_time,
                "time_bm": time_bm,
                "name": name
            }

            confirm_keyboard = {
                "inline_keyboard": [
                    [
                        {"text": "အတည်ပြုမယ် ✅", "callback_data": "action:confirm_bet"},
                        {"text": "မထိုးတော့ပါ ❌", "callback_data": "action:cancel_bet"}
                    ]
                ]
            }

            if len(parsed["items"]) == 1:
                r = parsed["items"][0]
                exp_count = len(r["expanded_numbers"])
                exp_str = ", ".join(r["expanded_numbers"])
                amt_str = format_num_amount(r["amount_per_number"])
                total_str = format_num_amount(r["total_amount"])

                preview_str = (
                    f"📝 ထိုးကြေးစာရင်း (အကြမ်း)\n\n"
                    f"ပွဲစဉ် - {session_bm}\n"
                    f"ထိုးကွက် - {r['input_value']} ({r['bet_type']})\n"
                    f"ဂဏန်း ({exp_count}) ကွက် - {exp_str}\n"
                    f"တစ်ကွက် - {amt_str} ကျပ်\n"
                    f"စုစုပေါင်း - {total_str} ကျပ်\n\n"
                    f"အပေါ်က ထိုးမယ့်စာရင်း မှန်/မမှန် တစ်ချက်စစ်ပေးပါ။\n"
                    f"မှန်တယ်ဆိုရင် အောက်က [အတည်ပြုမယ် ✅] ခလုတ်လေးကို နှိပ်ပေးပါ၊ (ဒါမှမဟုတ်) 'Confirm' လို့ စာပြန်ပေးပါ။"
                )
                send_telegram_message(chat_id, preview_str, reply_markup=confirm_keyboard)
            else:
                preview_lines = [
                    f"📝 ထိုးကြေးစာရင်း (အကြမ်း)\n",
                    f"ပွဲစဉ် - {session_bm}",
                    f"ထိုးခဲ့တဲ့အချိန် - {time_bm}\n",
                    "──────────────────────"
                ]

                for idx, r in enumerate(parsed["items"], 1):
                    exp_count = len(r["expanded_numbers"])
                    exp_preview = ", ".join(r["expanded_numbers"][:15])
                    if exp_count > 15:
                        exp_preview += f"... (+{exp_count - 15} ကွက်)"
                    amt_str = format_num_amount(r["amount_per_number"])
                    item_tot_str = format_num_amount(r["total_amount"])

                    line_str = (
                        f"{idx}️⃣ ထိုးကွက် - {r['input_value']} ({r['bet_type']})\n"
                        f"   ဂဏန်း ({exp_count}) ကွက် - {exp_preview}\n"
                        f"   တစ်ကွက် - {amt_str} ကျပ်\n"
                        f"   စုစုပေါင်း - {item_tot_str} ကျပ်"
                    )
                    preview_lines.append(line_str)

                grand_tot_str = format_num_amount(parsed["grand_total"])
                preview_lines.append("──────────────────────")
                preview_lines.append(f"💰 စုစုပေါင်း - {grand_tot_str} ကျပ်\n")
                preview_lines.append("အပေါ်က ထိုးမယ့်စာရင်း မှန်/မမှန် တစ်ချက်စစ်ပေးပါ။")
                preview_lines.append("မှန်တယ်ဆိုရင် အောက်က [အတည်ပြုမယ် ✅] ခလုတ်လေးကို နှိပ်ပေးပါ၊ (ဒါမှမဟုတ်) 'Confirm' လို့ စာပြန်ပေးပါ။")

                send_telegram_message(chat_id, "\n".join(preview_lines), reply_markup=confirm_keyboard)

            return {"status": "ok"}
        else:
            send_telegram_message(
                chat_id,
                "⚠️ ထိုးကြေးစာရင်းကို ဖတ်၍မရပါ သာဓက- 25-20r5000 သို့မဟုတ် 1/6ပတ်=250 ဟု ပို့ပေးပါ။"
            )

    elif "callback_query" in update:
        cb = update["callback_query"]
        chat_id = cb["message"]["chat"]["id"]
        data = cb["data"]
        active_chats.add(chat_id)

        if data == "action:confirm_bet":
            name = cb["message"]["chat"].get("first_name", "User")
            execute_bet_confirmation(chat_id, name)

        elif data == "action:cancel_bet":
            if chat_id in pending_confirmations:
                del pending_confirmations[chat_id]
            send_telegram_message(chat_id, "❌ ထိုးကြေးစာရင်းကို ဖျက်လိုက်ပါပြီ။")

    return {"status": "ok"}

# --- AUTOMATIC BACKGROUND TELEGRAM POLLING ---
def fetch_telegram_updates_sync(offset):
    url = f"{TELEGRAM_API_URL}/getUpdates?offset={offset}&timeout=10"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=12) as response:
            return json.loads(response.read().decode('utf-8'))
    except Exception as e:
        return None

@app.get("/")
def root():
    return {"status": "ok", "app": "2D Lottery API"}

async def telegram_polling_loop():
    offset = 0
    while True:
        try:
            data = await asyncio.to_thread(fetch_telegram_updates_sync, offset)
            if data and data.get("ok"):
                for update in data.get("result", []):
                    offset = update["update_id"] + 1
                    await telegram_webhook(update)
                await asyncio.sleep(1)
            elif data and not data.get("ok") and data.get("error_code") == 409:
                # Webhook is active on Cloud! Polling is not needed, sleep 60 seconds
                await asyncio.sleep(60)
            else:
                await asyncio.sleep(5)
        except Exception:
            await asyncio.sleep(5)

@app.on_event("startup")
async def startup_event():
    asyncio.create_task(telegram_polling_loop())
