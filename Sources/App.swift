import UIKit

// MARK: - Helpers

/// Minutes since midnight -> "08:30"
func timeString(_ minutes: Int) -> String {
    String(format: "%02d:%02d", minutes / 60, minutes % 60)
}

func minutesNow() -> Int {
    let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
    return (c.hour ?? 0) * 60 + (c.minute ?? 0)
}

/// 0 = Monday ... 5 = Saturday, nil = Sunday
func todayIndex() -> Int? {
    let weekday = Calendar(identifier: .gregorian).component(.weekday, from: Date()) // 1 = Sunday
    let index = weekday - 2
    return (0..<6).contains(index) ? index : nil
}

func dateFrom(minutes: Int) -> Date {
    Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
}

func minutesFrom(date: Date) -> Int {
    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
    return (c.hour ?? 0) * 60 + (c.minute ?? 0)
}

func durationString(_ minutes: Int) -> String {
    if minutes >= 60 {
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) ч" : "\(h) ч \(m) мин"
    }
    return "\(minutes) мин"
}

func lessonsWord(_ n: Int) -> String {
    let m10 = n % 10, m100 = n % 100
    if m10 == 1 && m100 != 11 { return "урок" }
    if (2...4).contains(m10) && !(12...14).contains(m100) { return "урока" }
    return "уроков"
}

// MARK: - Model

struct Lesson: Codable, Equatable {
    var id = UUID()
    var subject: String
    var start: Int // minutes since midnight
    var end: Int
    var room: String = ""
    var teacher: String = ""
}

final class ScheduleStore {
    static let shared = ScheduleStore()

    static let dayNames = ["Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота"]
    static let shortDayNames = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб"]

    /// Default bell schedule (start, end) in minutes since midnight.
    static let bells: [(Int, Int)] = [
        (8 * 60 + 30, 9 * 60 + 15),
        (9 * 60 + 25, 10 * 60 + 10),
        (10 * 60 + 30, 11 * 60 + 15),
        (11 * 60 + 35, 12 * 60 + 20),
        (12 * 60 + 30, 13 * 60 + 15),
        (13 * 60 + 25, 14 * 60 + 10),
        (14 * 60 + 20, 15 * 60 + 5),
    ]

    private let key = "schedule.v1"
    private(set) var days: [[Lesson]]

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([[Lesson]].self, from: data),
           decoded.count == 6 {
            days = decoded
        } else {
            days = ScheduleStore.sample()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(days) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func upsert(_ lesson: Lesson, day: Int) {
        if let i = days[day].firstIndex(where: { $0.id == lesson.id }) {
            days[day][i] = lesson
        } else {
            days[day].append(lesson)
        }
        days[day].sort { $0.start < $1.start }
        save()
    }

    func delete(id: UUID, day: Int) {
        days[day].removeAll { $0.id == id }
        save()
    }

    func clear(day: Int) {
        days[day] = []
        save()
    }

    func copy(day: Int, to target: Int) {
        days[target] = days[day].map { lesson in
            var copy = lesson
            copy.id = UUID()
            return copy
        }
        save()
    }

    func resetToSample() {
        days = ScheduleStore.sample()
        save()
    }

    func allSubjects() -> [String] {
        Array(Set(days.flatMap { $0 }.map { $0.subject })).sorted()
    }

    func anyLesson(subject: String) -> Lesson? {
        days.flatMap { $0 }.first { $0.subject == subject }
    }

    func suggestedLesson(day: Int) -> Lesson {
        let list = days[day]
        var start: Int
        var end: Int
        if list.count < ScheduleStore.bells.count,
           list.last.map({ $0.end <= ScheduleStore.bells[list.count].0 }) ?? true {
            let bell = ScheduleStore.bells[list.count]
            start = bell.0
            end = bell.1
        } else {
            start = (list.last?.end ?? ScheduleStore.bells[0].0) + 10
            end = start + 45
        }
        start = min(start, 23 * 60)
        end = min(end, 23 * 60 + 59)
        return Lesson(subject: "", start: start, end: end)
    }

    static func sample() -> [[Lesson]] {
        let plan: [[String]] = [
            ["Математика", "Русский язык", "Литература", "Английский язык", "Физика", "Физкультура"],
            ["Алгебра", "История", "Биология", "Русский язык", "Информатика", "География"],
            ["Геометрия", "Химия", "Английский язык", "Литература", "Обществознание", "Физкультура"],
            ["Алгебра", "Физика", "Русский язык", "История", "Биология", "Технология"],
            ["Геометрия", "Английский язык", "Химия", "Литература", "Информатика"],
            ["Математика", "География", "Музыка", "Физкультура"],
        ]
        let rooms: [String: String] = [
            "Математика": "21", "Алгебра": "21", "Геометрия": "21",
            "Русский язык": "14", "Литература": "14",
            "Английский язык": "32", "Физика": "25", "Химия": "27",
            "Биология": "18", "История": "11", "Обществознание": "11",
            "География": "16", "Информатика": "30", "Физкультура": "Спортзал",
            "Технология": "5", "Музыка": "8",
        ]
        return plan.map { subjects in
            subjects.enumerated().map { i, subject in
                Lesson(subject: subject, start: bells[i].0, end: bells[i].1, room: rooms[subject] ?? "")
            }
        }
    }
}

// MARK: - Badge

final class BadgeLabel: UILabel {
    convenience init(text: String, color: UIColor) {
        self.init(frame: .zero)
        self.text = text
        font = .systemFont(ofSize: 13, weight: .semibold)
        textColor = .white
        backgroundColor = color
        textAlignment = .center
        clipsToBounds = true
        frame = CGRect(origin: .zero, size: intrinsicContentSize)
        layer.cornerRadius = frame.height / 2
    }

    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(width: s.width + 16, height: s.height + 6)
    }
}

// MARK: - Schedule screen

final class ScheduleViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private enum LessonState { case past, current, next, normal }

    private let store = ScheduleStore.shared
    private let segmented = UISegmentedControl(items: ScheduleStore.shortDayNames)
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyLabel = UILabel()
    private var day = 0
    private var timer: Timer?

    private var lessons: [Lesson] { store.days[day] }
    private var isToday: Bool { day == todayIndex() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Расписание"
        view.backgroundColor = .systemGroupedBackground

        day = todayIndex() ?? 0
        segmented.selectedSegmentIndex = day
        segmented.addTarget(self, action: #selector(dayChanged), for: .valueChanged)
        segmented.translatesAutoresizingMaskIntoConstraints = false

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.backgroundColor = .clear

        emptyLabel.text = "На этот день уроков нет.\nНажмите «+», чтобы добавить."
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = .secondaryLabel
        emptyLabel.font = .preferredFont(forTextStyle: .body)

        view.addSubview(segmented)
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            segmented.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            segmented.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            segmented.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: segmented.bottomAnchor, constant: 4),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add, target: self, action: #selector(addLesson))
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: nil, image: UIImage(systemName: "ellipsis.circle"), primaryAction: nil, menu: makeMenu())

        NotificationCenter.default.addObserver(
            self, selector: #selector(refresh),
            name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        timer?.invalidate()
        timer = nil
    }

    // MARK: Actions

    @objc private func dayChanged() {
        day = segmented.selectedSegmentIndex
        navigationItem.leftBarButtonItem?.menu = makeMenu()
        reload()
    }

    @objc private func refresh() {
        guard !tableView.isEditing, presentedViewController == nil else { return }
        reload()
    }

    private func reload() {
        tableView.backgroundView = lessons.isEmpty ? emptyLabel : nil
        tableView.reloadData()
    }

    private func goToday() {
        guard let today = todayIndex() else {
            showMessage("Сегодня воскресенье — уроков нет 🙂")
            return
        }
        segmented.selectedSegmentIndex = today
        dayChanged()
    }

    @objc private func addLesson() {
        openEditor(nil)
    }

    private func openEditor(_ lesson: Lesson?) {
        let dayIndex = day
        let editor = LessonEditorViewController(
            lesson: lesson ?? store.suggestedLesson(day: dayIndex),
            isNew: lesson == nil,
            dayName: ScheduleStore.dayNames[dayIndex])
        editor.onSave = { [weak self] saved in
            self?.store.upsert(saved, day: dayIndex)
            self?.reload()
        }
        editor.onDelete = { [weak self] deleted in
            self?.store.delete(id: deleted.id, day: dayIndex)
            self?.reload()
        }
        present(UINavigationController(rootViewController: editor), animated: true)
    }

    private func makeMenu() -> UIMenu {
        let today = UIAction(title: "Перейти к сегодня", image: UIImage(systemName: "calendar")) { [weak self] _ in
            self?.goToday()
        }
        let targets = (0..<6).filter { $0 != day }.map { target -> UIAction in
            UIAction(title: ScheduleStore.dayNames[target]) { [weak self] _ in
                self?.confirmCopy(to: target)
            }
        }
        let copy = UIMenu(title: "Скопировать день в…", image: UIImage(systemName: "doc.on.doc"), children: targets)
        let reset = UIAction(title: "Восстановить пример", image: UIImage(systemName: "arrow.counterclockwise")) { [weak self] _ in
            self?.confirm(title: "Восстановить пример?",
                          message: "Всё текущее расписание будет заменено примером.",
                          action: "Восстановить") {
                self?.store.resetToSample()
                self?.reload()
            }
        }
        let clear = UIAction(title: "Очистить день", image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
            guard let self = self else { return }
            let dayIndex = self.day
            self.confirm(title: "Очистить \(ScheduleStore.dayNames[dayIndex].lowercased())?",
                         message: "Все уроки этого дня будут удалены.",
                         action: "Очистить", destructive: true) {
                self.store.clear(day: dayIndex)
                self.reload()
            }
        }
        return UIMenu(title: "", children: [today, copy, reset, clear])
    }

    private func confirmCopy(to target: Int) {
        let source = day
        confirm(title: "Скопировать в «\(ScheduleStore.dayNames[target])»?",
                message: "Уроки этого дня заменят текущие уроки на \(ScheduleStore.shortDayNames[target]).",
                action: "Скопировать") { [weak self] in
            self?.store.copy(day: source, to: target)
            self?.segmented.selectedSegmentIndex = target
            self?.dayChanged()
        }
    }

    private func confirm(title: String, message: String, action: String,
                         destructive: Bool = false, handler: @escaping () -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: action, style: destructive ? .destructive : .default) { _ in handler() })
        present(alert, animated: true)
    }

    private func showMessage(_ text: String) {
        let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: Status

    private func state(of lesson: Lesson) -> LessonState {
        guard isToday else { return .normal }
        let now = minutesNow()
        if lesson.start <= now && now < lesson.end { return .current }
        if lesson.end <= now { return .past }
        let hasCurrent = lessons.contains { $0.start <= now && now < $0.end }
        if !hasCurrent, lessons.first(where: { $0.start > now })?.id == lesson.id { return .next }
        return .normal
    }

    private func statusText() -> String? {
        guard isToday, let first = lessons.first else { return nil }
        let now = minutesNow()
        if let current = lessons.first(where: { $0.start <= now && now < $0.end }) {
            return "Сейчас: \(current.subject), до конца \(durationString(current.end - now))"
        }
        if let next = lessons.first(where: { $0.start > now }) {
            let wait = durationString(next.start - now)
            if now < first.start {
                return "Первый урок: \(next.subject) в \(timeString(next.start)) (через \(wait))"
            }
            return "Перемена. Далее: \(next.subject) в \(timeString(next.start)) (через \(wait))"
        }
        return "Уроки на сегодня закончились 🎉"
    }

    // MARK: Table

    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        lessons.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard !lessons.isEmpty else { return nil }
        let name = ScheduleStore.dayNames[day]
        return isToday ? "\(name) · сегодня" : name
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let first = lessons.first, let last = lessons.last else { return nil }
        var text = "\(lessons.count) \(lessonsWord(lessons.count)) · \(timeString(first.start)) – \(timeString(last.end))"
        if let status = statusText() { text += "\n\(status)" }
        return text
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "lesson")
            ?? UITableViewCell(style: .default, reuseIdentifier: "lesson")
        let lesson = lessons[indexPath.row]
        let lessonState = state(of: lesson)

        var content = UIListContentConfiguration.subtitleCell()
        content.text = lesson.subject
        content.textProperties.font = .preferredFont(forTextStyle: .headline)
        var details = ["\(timeString(lesson.start)) – \(timeString(lesson.end))"]
        if !lesson.room.isEmpty {
            details.append(Int(lesson.room) != nil ? "каб. \(lesson.room)" : lesson.room)
        }
        if !lesson.teacher.isEmpty { details.append(lesson.teacher) }
        content.secondaryText = details.joined(separator: " · ")
        content.secondaryTextProperties.color = .secondaryLabel
        content.textToSecondaryTextVerticalPadding = 4
        content.image = UIImage(systemName: "\(min(indexPath.row + 1, 50)).circle.fill")
        content.imageProperties.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 26)

        switch lessonState {
        case .current:
            content.imageProperties.tintColor = .systemGreen
            cell.accessoryView = BadgeLabel(text: "Сейчас", color: .systemGreen)
        case .next:
            content.imageProperties.tintColor = .systemOrange
            cell.accessoryView = BadgeLabel(text: "Далее", color: .systemOrange)
        case .past:
            content.imageProperties.tintColor = .systemGray3
            content.textProperties.color = .secondaryLabel
            cell.accessoryView = nil
        case .normal:
            content.imageProperties.tintColor = .systemIndigo
            cell.accessoryView = nil
        }
        cell.contentConfiguration = content
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        openEditor(lessons[indexPath.row])
    }

    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let lesson = lessons[indexPath.row]
        let dayIndex = day
        let delete = UIContextualAction(style: .destructive, title: "Удалить") { [weak self] _, _, done in
            guard let self = self else { return done(false) }
            self.store.delete(id: lesson.id, day: dayIndex)
            tableView.performBatchUpdates({
                tableView.deleteRows(at: [indexPath], with: .automatic)
            }, completion: { _ in
                self.reload()
            })
            done(true)
        }
        delete.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [delete])
    }
}

// MARK: - Lesson editor

final class LessonEditorViewController: UITableViewController, UITextFieldDelegate {
    var onSave: ((Lesson) -> Void)?
    var onDelete: ((Lesson) -> Void)?

    private var lesson: Lesson
    private let isNew: Bool
    private let dayName: String
    private var lastStart: Int

    private let subjectField = UITextField()
    private let roomField = UITextField()
    private let teacherField = UITextField()
    private let startPicker = UIDatePicker()
    private let endPicker = UIDatePicker()

    private var sections: [[UITableViewCell]] = []
    private var sectionTitles: [String?] = []
    private var deleteSection: Int?

    init(lesson: Lesson, isNew: Bool, dayName: String) {
        self.lesson = lesson
        self.isNew = isNew
        self.dayName = dayName
        self.lastStart = lesson.start
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = isNew ? "Новый урок" : "Урок"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .save, target: self, action: #selector(save))

        setup(subjectField, placeholder: "Например, Математика", text: lesson.subject)
        subjectField.autocapitalizationType = .sentences
        setup(roomField, placeholder: "Номер кабинета", text: lesson.room)
        setup(teacherField, placeholder: "ФИО учителя", text: lesson.teacher)
        teacherField.autocapitalizationType = .words
        teacherField.returnKeyType = .done
        addSubjectMenu()

        setup(startPicker, minutes: lesson.start)
        setup(endPicker, minutes: lesson.end)
        startPicker.addTarget(self, action: #selector(startChanged), for: .valueChanged)

        sections = [
            [fieldCell("Предмет", subjectField), fieldCell("Кабинет", roomField), fieldCell("Учитель", teacherField)],
            [pickerCell("Начало", startPicker), pickerCell("Конец", endPicker)],
        ]
        sectionTitles = [dayName, "Время"]
        if !isNew {
            deleteSection = sections.count
            sections.append([deleteCell()])
            sectionTitles.append(nil)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if isNew { subjectField.becomeFirstResponder() }
    }

    // MARK: Building cells

    private func setup(_ field: UITextField, placeholder: String, text: String) {
        field.placeholder = placeholder
        field.text = text
        field.clearButtonMode = .whileEditing
        field.returnKeyType = .next
        field.delegate = self
        field.font = .preferredFont(forTextStyle: .body)
    }

    private func setup(_ picker: UIDatePicker, minutes: Int) {
        picker.datePickerMode = .time
        picker.preferredDatePickerStyle = .compact
        picker.locale = Locale(identifier: "ru_RU")
        picker.date = dateFrom(minutes: minutes)
    }

    private func addSubjectMenu() {
        let subjects = ScheduleStore.shared.allSubjects()
        guard !subjects.isEmpty else { return }
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "list.bullet.circle"), for: .normal)
        button.frame = CGRect(x: 0, y: 0, width: 32, height: 32)
        button.menu = UIMenu(title: "Выбрать предмет", children: subjects.map { subject in
            UIAction(title: subject) { [weak self] _ in self?.pickSubject(subject) }
        })
        button.showsMenuAsPrimaryAction = true
        subjectField.rightView = button
        subjectField.rightViewMode = .unlessEditing
    }

    private func pickSubject(_ subject: String) {
        subjectField.text = subject
        guard let other = ScheduleStore.shared.anyLesson(subject: subject) else { return }
        if (roomField.text ?? "").isEmpty { roomField.text = other.room }
        if (teacherField.text ?? "").isEmpty { teacherField.text = other.teacher }
    }

    private func fieldCell(_ title: String, _ field: UITextField) -> UITableViewCell {
        let cell = UITableViewCell()
        cell.selectionStyle = .none
        let label = makeTitleLabel(title)
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(label)
        cell.contentView.addSubview(field)
        let guide = cell.contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: 90),
            field.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            field.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            field.topAnchor.constraint(equalTo: guide.topAnchor),
            field.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            field.heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
        ])
        return cell
    }

    private func pickerCell(_ title: String, _ picker: UIDatePicker) -> UITableViewCell {
        let cell = UITableViewCell()
        cell.selectionStyle = .none
        let label = makeTitleLabel(title)
        picker.translatesAutoresizingMaskIntoConstraints = false
        cell.contentView.addSubview(label)
        cell.contentView.addSubview(picker)
        let guide = cell.contentView.layoutMarginsGuide
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            label.centerYAnchor.constraint(equalTo: cell.contentView.centerYAnchor),
            picker.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            picker.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 6),
            picker.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -6),
            picker.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 8),
        ])
        return cell
    }

    private func deleteCell() -> UITableViewCell {
        let cell = UITableViewCell()
        var content = cell.defaultContentConfiguration()
        content.text = "Удалить урок"
        content.textProperties.color = .systemRed
        content.textProperties.alignment = .center
        cell.contentConfiguration = content
        return cell
    }

    private func makeTitleLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .body)
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    // MARK: Actions

    @objc private func startChanged() {
        let newStart = minutesFrom(date: startPicker.date)
        let duration = minutesFrom(date: endPicker.date) - lastStart
        if duration > 0 {
            endPicker.setDate(dateFrom(minutes: min(newStart + duration, 23 * 60 + 59)), animated: true)
        }
        lastStart = newStart
    }

    @objc private func cancel() {
        dismiss(animated: true)
    }

    @objc private func save() {
        let subject = (subjectField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !subject.isEmpty else {
            showError("Введите название предмета")
            return
        }
        let start = minutesFrom(date: startPicker.date)
        let end = minutesFrom(date: endPicker.date)
        guard end > start else {
            showError("Урок должен заканчиваться позже, чем начинается")
            return
        }
        lesson.subject = subject
        lesson.room = (roomField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        lesson.teacher = (teacherField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        lesson.start = start
        lesson.end = end
        onSave?(lesson)
        dismiss(animated: true)
    }

    private func confirmDelete() {
        let alert = UIAlertController(title: "Удалить урок?", message: lesson.subject, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Удалить", style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            self.onDelete?(self.lesson)
            self.dismiss(animated: true)
        })
        present(alert, animated: true)
    }

    private func showError(_ text: String) {
        let alert = UIAlertController(title: nil, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: UITextFieldDelegate

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === subjectField {
            roomField.becomeFirstResponder()
        } else if textField === roomField {
            teacherField.becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
        }
        return true
    }

    // MARK: Table

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        sections[indexPath.section][indexPath.row]
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sectionTitles[section]
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == deleteSection { confirmDelete() }
    }
}

// MARK: - App

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.tintColor = .systemIndigo
        window.rootViewController = UINavigationController(rootViewController: ScheduleViewController())
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}
