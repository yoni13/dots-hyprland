const weekDays = [ // MONDAY IS THE FIRST DAY OF THE WEEK :HESRIGHTYOUKNOW:
    { day: 'Mo', today: 0 },
    { day: 'Tu', today: 0 },
    { day: 'We', today: 0 },
    { day: 'Th', today: 0 },
    { day: 'Fr', today: 0 },
    { day: 'Sa', today: 0 },
    { day: 'Su', today: 0 },
]

function checkLeapYear(year) {
    return (
        year % 400 == 0 ||
        (year % 4 == 0 && year % 100 != 0));
}

function getMonthDays(month, year) {
    const leapYear = checkLeapYear(year);
    if ((month <= 7 && month % 2 == 1) || (month >= 8 && month % 2 == 0)) return 31;
    if (month == 2 && leapYear) return 29;
    if (month == 2 && !leapYear) return 28;
    return 30;
}

function getNextMonthDays(month, year) {
    const leapYear = checkLeapYear(year);
    if (month == 1 && leapYear) return 29;
    if (month == 1 && !leapYear) return 28;
    if (month == 12) return 31;
    if ((month <= 7 && month % 2 == 1) || (month >= 8 && month % 2 == 0)) return 30;
    return 31;
}

function getPrevMonthDays(month, year) {
    const leapYear = checkLeapYear(year);
    if (month == 3 && leapYear) return 29;
    if (month == 3 && !leapYear) return 28;
    if (month == 1) return 31;
    if ((month <= 7 && month % 2 == 1) || (month >= 8 && month % 2 == 0)) return 30;
    return 31;
}

function getDateInXMonthsTime(x) {
    var currentDate = new Date(); // Get the current date
    if (x == 0) return currentDate; // If x is 0, return the current date

    var targetMonth = currentDate.getMonth() + x; // Calculate the target month
    var targetYear = currentDate.getFullYear(); // Get the current year

    // Adjust the year and month if necessary
    targetYear += Math.floor(targetMonth / 12);
    targetMonth = (targetMonth % 12 + 12) % 12;

    // Create a new date object with the target year and month
    var targetDate = new Date(targetYear, targetMonth, 1);

    // Set the day to the last day of the month to get the desired date
    // targetDate.setDate(0);

    return targetDate;
}

function getCalendarLayout(dateObject, highlight) {
    if (!dateObject) dateObject = new Date();
    const month = dateObject.getMonth();
    const year = dateObject.getFullYear();
    const today = new Date();
    const firstWeekday = (new Date(year, month, 1).getDay() + 6) % 7;
    const firstDate = new Date(year, month, 1 - firstWeekday);
    const pad = value => String(value).padStart(2, "0");
    const calendar = [...Array(6)].map(() => Array(7));

    for (let index = 0; index < 42; index++) {
        const date = new Date(firstDate.getFullYear(), firstDate.getMonth(), firstDate.getDate() + index);
        const inDisplayedMonth = date.getMonth() === month;
        const isToday = highlight
            && date.getFullYear() === today.getFullYear()
            && date.getMonth() === today.getMonth()
            && date.getDate() === today.getDate();
        calendar[Math.floor(index / 7)][index % 7] = {
            "day": date.getDate(),
            "today": isToday ? 1 : (inDisplayedMonth ? 0 : -1),
            "dateKey": `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`
        };
    }
    return calendar;
}
