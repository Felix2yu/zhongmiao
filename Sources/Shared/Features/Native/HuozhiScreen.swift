import SwiftUI
import ZhongmiaoCore

struct HuozhiScreen: View {

    @Environment(AppModel.self) private var model

    let service: ServiceDefinition
    let baseURL: URL
    let definition: IntegrationDefinition

    @State private var store: HuozhiModel
    @State private var showCredential = false
    @State private var entry: EntryRequest?
    @State private var expandedTransactionID: Int?

    private struct EntryRequest: Identifiable {
        let id = UUID()
        var kind: HuozhiEntryKind
        var creditAccountID: Int?
    }

    init(
        service: ServiceDefinition,
        baseURL: URL,
        definition: IntegrationDefinition,
        center: IntegrationCenter
    ) {
        self.service = service
        self.baseURL = baseURL
        self.definition = definition
        _store = State(initialValue: HuozhiModel(service: service, baseURL: baseURL, center: center))
    }

    var body: some View {
        List {
            Section {
                assetCard
                    .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
            }

            if let state = bannerState {
                Section {
                    IntegrationStatusBanner(
                        state: state,
                        error: store.error ?? store.center.lastErrors["huozhi"],
                        onConfigure: { showCredential = true },
                        onRetry: { Task { await store.refresh() } }
                    )
                    .listRowInsets(EdgeInsets())
                }
            }

            Section {
                Button {
                    startEntry(.expense)
                } label: {
                    Label("记一笔", systemImage: "square.and.pencil")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            if store.books.count > 1 {
                Section {
                    Picker(
                        "账本",
                        selection: Binding(
                            get: { store.selectedBookID ?? store.books.first?.id ?? 0 },
                            set: { store.selectBook($0) }
                        )
                    ) {
                        ForEach(store.books) { book in
                            Text(book.name).tag(book.id)
                        }
                    }
                } header: {
                    Text("账本")
                }
            }

            if !store.creditCards.isEmpty {
                Section {
                    ForEach(store.creditCards) { card in
                        Button {
                            startEntry(.repayment, creditAccountID: card.id)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "creditcard")
                                    .foregroundStyle(.orange)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(card.name)
                                        .font(.subheadline.weight(.medium))
                                    Text(creditSubtitle(card))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 6)
                                Text(money(card.balance))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(card.balance > 0 ? .orange : .secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("信用卡还款")
                }
            }

            if store.recentGroups.isEmpty {
                Section {
                    EmptyStateView(
                        symbol: "list.bullet.rectangle",
                        title: "还没有流水",
                        message: "记一笔支出、收入或转账，会直接同步到货殖。"
                    )
                    .listRowBackground(Color.clear)
                }
            } else {
                ForEach(store.recentGroups) { group in
                    Section {
                        ForEach(group.transactions) { transaction in
                            transactionRow(transaction)
                        }
                    } header: {
                        HStack {
                            Text(dayLabel(group.date))
                            Spacer()
                            Text(summaryText(group))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(service.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    startEntry(.expense)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("记一笔")
            }
            ToolbarItem(placement: .primaryAction) {
                IntegrationScreenMenu(service: service, definition: definition) {
                    Task { await store.refresh() }
                }
            }
        }
        .refreshable {
            await store.refresh()
        }
        .task {
            await store.loadCache()
            await store.refreshIfNeeded()
        }
        .refreshWhenIntegrationReady(center: store.center, serviceID: "huozhi") {
            Task { await store.refresh() }
        }
        .onChange(of: model.network.isOnline) { _, online in
            if online { Task { await store.refresh() } }
        }
        .sheet(item: $entry) { request in
            HuozhiEntrySheet(
                store: store,
                initialKind: request.kind,
                presetCreditAccountID: request.creditAccountID
            )
        }
        .sheet(isPresented: $showCredential) {
            CredentialSheet(definition: definition, service: service)
        }
    }

    private var bannerState: IntegrationCenter.CredentialState? {
        let state = store.center.state(for: "huozhi")
        if state.isUsable && store.error == nil { return nil }
        return state
    }

    private var assetCard: some View {
        let assets = store.snapshot?.assets
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("净资产")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(money(assets?.netAsset ?? store.snapshot?.accountSummary?.netAsset ?? 0))
                        .font(.title2.weight(.semibold).monospacedDigit())
                }
                Spacer()
                if let last = store.lastUpdated {
                    Text(RelativeTime.short(last))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 16) {
                assetMetric("总资产", value: assets?.totalAsset ?? store.snapshot?.accountSummary?.totalAsset ?? 0, tint: .green)
                assetMetric("总负债", value: assets?.totalDebt ?? store.snapshot?.accountSummary?.totalDebt ?? 0, tint: .red)
                assetMetric("本月支出", value: assets?.monthExpense ?? 0, tint: .orange)
            }
        }
        .padding(14)
        .background(Color.zmCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.separator.opacity(0.35))
        }
    }

    private func assetMetric(_ title: String, value: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(money(value))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func transactionRow(_ transaction: HuozhiTransaction) -> some View {
        let expanded = expandedTransactionID == transaction.id
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    expandedTransactionID = expanded ? nil : transaction.id
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: typeSymbol(transaction.type))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(typeTint(transaction.type))
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(transaction.description?.isEmpty == false ? transaction.description! : (transaction.categoryName ?? typeTitle(transaction.type)))
                            .font(.subheadline)
                            .lineLimit(1)
                        Text(subtitle(transaction))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 6)

                    Text(amountText(transaction))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(typeTint(transaction.type))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 5) {
                    Label(transaction.txDate.replacingOccurrences(of: "T", with: " ").prefix(16).description, systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let category = transaction.categoryName {
                        Label(category, systemImage: "tag")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let remark = transaction.remark, !remark.isEmpty {
                        Text(remark)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.leading, 32)
                .transition(.opacity)
            }
        }
        .padding(.vertical, 2)
    }

    private func startEntry(_ kind: HuozhiEntryKind, creditAccountID: Int? = nil) {
        guard store.center.state(for: "huozhi").isUsable else {
            showCredential = true
            return
        }
        entry = EntryRequest(kind: kind, creditAccountID: creditAccountID)
    }

    private func creditSubtitle(_ card: HuozhiCreditCard) -> String {
        var parts: [String] = []
        if let bank = card.bankName, !bank.isEmpty { parts.append(bank) }
        if let day = card.repayDay { parts.append("\(day) 日还款") }
        if let left = card.daysLeft {
            parts.append(left < 0 ? "已逾期 \(abs(left)) 天" : "还有 \(left) 天")
        }
        return parts.isEmpty ? "信用卡" : parts.joined(separator: " · ")
    }

    private func dayLabel(_ raw: String) -> String {
        guard let date = QiansiLocalDate.parse(raw) else { return raw }
        if Calendar.current.isDateInToday(date) { return "今天" }
        if Calendar.current.isDateInYesterday(date) { return "昨天" }
        return date.formatted(.dateTime.month().day().weekday(.abbreviated))
    }

    private func summaryText(_ group: HuozhiDayGroup) -> String {
        var parts: [String] = []
        if let expense = group.dayExpense, expense != 0 { parts.append("支出 \(money(expense))") }
        if let income = group.dayIncome, income != 0 { parts.append("收入 \(money(income))") }
        return parts.joined(separator: " · ")
    }

    private func subtitle(_ transaction: HuozhiTransaction) -> String {
        var parts: [String] = []
        if let account = transaction.accountName, !account.isEmpty { parts.append(account) }
        if let to = transaction.toAccountName, !to.isEmpty { parts.append("→ \(to)") }
        if parts.isEmpty { parts.append(typeTitle(transaction.type)) }
        return parts.joined(separator: " ")
    }

    private func amountText(_ transaction: HuozhiTransaction) -> String {
        let sign = transaction.isExpenseLike ? "-" : (transaction.isIncomeLike ? "+" : "")
        return sign + money(transaction.amount)
    }

    private func typeTint(_ type: String) -> Color {
        switch type {
        case "expense", "reimburse": .red
        case "income", "refund": .green
        case "transfer": .blue
        default: .secondary
        }
    }

    private func typeSymbol(_ type: String) -> String {
        switch type {
        case "expense", "reimburse": "arrow.up.right"
        case "income", "refund": "arrow.down.left"
        case "transfer": "arrow.left.arrow.right"
        default: "circle"
        }
    }

    private func typeTitle(_ type: String) -> String {
        switch type {
        case "expense": "支出"
        case "income": "收入"
        case "transfer": "转账"
        case "refund": "退款"
        case "reimburse": "报销"
        case "adjust": "余额调整"
        default: type
        }
    }
}

private struct HuozhiEntrySheet: View {

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let store: HuozhiModel
    let presetCreditAccountID: Int?

    @State private var draft: HuozhiDraft
    @State private var amountText = ""
    @State private var entryDate = Date()
    @State private var note = ""
    @State private var isSaving = false
    @State private var message: String?
    @State private var didPrepare = false

    init(store: HuozhiModel, initialKind: HuozhiEntryKind, presetCreditAccountID: Int?) {
        self.store = store
        self.presetCreditAccountID = presetCreditAccountID
        _draft = State(initialValue: HuozhiDraft(
            kind: initialKind,
            date: QiansiLocalDate.dayString(Date())
        ))
    }

    private var book: HuozhiBook? {
        store.books.first { $0.id == draft.bookID }
    }

    private var categoryOptions: [HuozhiCategoryOption] {
        draft.kind == .income ? store.incomeOptions : store.expenseOptions
    }

    private var sourceAccounts: [HuozhiAccount] {
        if draft.kind == .repayment { return store.paymentAccounts }
        return store.accounts
    }

    private var targetAccounts: [HuozhiAccount] {
        if draft.kind == .repayment { return store.creditAccounts }
        return store.accounts.filter { $0.id != draft.accountID }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("类型", selection: $draft.kind) {
                        ForEach(HuozhiEntryKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("金额", text: $amountText)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .font(.title3.monospacedDigit())

                    DatePicker("日期", selection: $entryDate, displayedComponents: .date)

                    if let book {
                        LabeledContent("账本", value: book.name)
                    }
                } header: {
                    Text("记账")
                } footer: {
                    if let book {
                        Text("记入「\(book.name)」；要换账本请先在列表页切换。")
                    } else {
                        Text("还没有可用账本，请先在网页版创建。")
                    }
                }

                if draft.kind == .expense || draft.kind == .income {
                    Section {
                        Picker("分类", selection: $draft.categoryID) {
                            Text("未分类").tag(0)
                            ForEach(categoryOptions) { option in
                                Text(option.title).tag(option.id)
                            }
                        }
                        Picker("账户", selection: $draft.accountID) {
                            ForEach(sourceAccounts) { account in
                                Text(account.name).tag(account.id)
                            }
                        }
                    } header: {
                        Text("分类与账户")
                    }
                }

                if draft.kind == .transfer {
                    Section {
                        Picker("转出账户", selection: $draft.accountID) {
                            ForEach(sourceAccounts) { account in
                                Text(account.name).tag(account.id)
                            }
                        }
                        Picker("转入账户", selection: Binding(
                            get: { draft.toAccountID ?? 0 },
                            set: { draft.toAccountID = $0 == 0 ? nil : $0 }
                        )) {
                            Text("请选择").tag(0)
                            ForEach(targetAccounts) { account in
                                Text(account.name).tag(account.id)
                            }
                        }
                    } header: {
                        Text("转账账户")
                    }
                }

                if draft.kind == .repayment {
                    Section {
                        Picker("付款账户", selection: $draft.accountID) {
                            ForEach(sourceAccounts) { account in
                                Text(account.name).tag(account.id)
                            }
                        }
                        Picker("信用卡", selection: Binding(
                            get: { draft.toAccountID ?? 0 },
                            set: { draft.toAccountID = $0 == 0 ? nil : $0 }
                        )) {
                            Text("请选择").tag(0)
                            ForEach(targetAccounts) { account in
                                Text(account.name).tag(account.id)
                            }
                        }
                    } header: {
                        Text("还款账户")
                    } footer: {
                        Text("信用卡还款会记为一笔转账，从付款账户转到信用卡，直接减少欠款。")
                    }
                }

                Section {
                    TextField("备注（可选）", text: $note)
                } header: {
                    Text("备注")
                }

                if let message {
                    Section {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(draft.needsReconciliation ? .orange : .red)
                    }
                }

                if draft.needsReconciliation {
                    Section {
                        Button("重新核对流水") {
                            Task { await reconcile() }
                        }
                        .disabled(isSaving)
                        Button("确认未保存，重新提交") {
                            draft.allowResubmit()
                            message = nil
                        }
                        .disabled(isSaving)
                    }
                }

                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        HStack {
                            if isSaving { ProgressView().controlSize(.small) }
                            Text(isSaving ? "正在提交…" : "保存到货殖")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isSaving || !draft.canSubmit || draft.bookID == 0)
                }
            }
            .navigationTitle("记一笔")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isSaving)
                }
            }
            .task { prepare() }
            .onChange(of: draft.kind) { _, kind in
                draft.categoryID = 0
                draft.toAccountID = nil
                if kind == .repayment {
                    draft.toAccountID = presetCreditAccountID ?? store.creditAccounts.first?.id
                    draft.accountID = store.paymentAccounts.first?.id ?? draft.accountID
                } else if kind == .transfer {
                    draft.accountID = store.accounts.first?.id ?? draft.accountID
                }
                updateDraftFromFields()
            }
            .onChange(of: draft.accountID) { _, _ in
                if draft.kind == .transfer, draft.toAccountID == draft.accountID {
                    draft.toAccountID = nil
                }
                updateDraftFromFields()
            }
            .onChange(of: draft.toAccountID) { _, _ in
                if draft.kind == .repayment, let account = store.account(id: draft.toAccountID) {
                    amountText = String(format: "%.2f", account.balance)
                    updateDraftFromFields()
                }
            }
            .onChange(of: amountText) { _, _ in updateDraftFromFields() }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func prepare() {
        guard !didPrepare else { return }
        didPrepare = true
        draft.bookID = store.selectedBookID ?? store.books.first?.id ?? 0
        draft.accountID = store.accounts.first?.id ?? 0
        if draft.kind == .transfer {
            draft.toAccountID = store.accounts.first { $0.id != draft.accountID }?.id
        }
        if draft.kind == .repayment {
            draft.accountID = store.paymentAccounts.first?.id ?? draft.accountID
            draft.toAccountID = presetCreditAccountID ?? store.creditAccounts.first?.id
            if let account = store.account(id: draft.toAccountID) {
                amountText = String(format: "%.2f", account.balance)
            }
        }
        updateDraftFromFields()
    }

    private func updateDraftFromFields() {
        let normalized = amountText.replacingOccurrences(of: ",", with: ".")
        draft.amount = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) ?? 0
        draft.date = QiansiLocalDate.dayString(entryDate)
        draft.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() async {
        updateDraftFromFields()
        guard let book else {
            message = "没有可用账本"
            return
        }
        if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.note = draft.kind == .repayment ? "信用卡还款" : ""
        }
        draft.beginSubmit()
        isSaving = true
        message = nil

        let outcome = await store.submit(
            draft,
            currency: book.currency ?? store.currency(for: draft.accountID)
        )
        isSaving = false

        switch outcome {
        case .saved:
            model.toast = "已记账"
            dismiss()
        case .unknown:
            draft.markUnknown()
            message = "请求超时，可能已经保存。先核对最近流水，确认没有这笔再重新提交。"
        case .failed(let reason):
            draft.state = .draft
            message = reason
        }
    }

    private func reconcile() async {
        isSaving = true
        let found = await store.reconcile(draft)
        isSaving = false
        if found {
            model.toast = "已找到这笔流水"
            dismiss()
        } else {
            message = "最近流水里没有找到这笔，可能是服务端也没保存。可以确认后重新提交。"
        }
    }
}

private func money(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(2)))
}
