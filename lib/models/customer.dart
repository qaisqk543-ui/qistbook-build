/// Data models for QistBook.
/// A Customer is keyed by [accountNo] (the "A/C No." on your prints) —
/// that is the link between the detail statement and the outstanding report.

enum AccountStatus {
  /// In the latest outstanding list, or newly created.
  active,
  /// Was active but missing from the newest outstanding import → qist finished.
  cleared,
  /// Current due > 0 and last installment date is past → needs follow-up.
  overdue,
}

class Guarantor {
  final String name;
  final String cnic;
  final String address;
  final String phone;

  Guarantor({this.name = '', this.cnic = '', this.address = '', this.phone = ''});

  Map<String, dynamic> toMap() => {
        'name': name,
        'cnic': cnic,
        'address': address,
        'phone': phone,
      };

  factory Guarantor.fromMap(Map<String, dynamic> m) => Guarantor(
        name: (m['name'] ?? '').toString(),
        cnic: (m['cnic'] ?? '').toString(),
        address: (m['address'] ?? '').toString(),
        phone: (m['phone'] ?? '').toString(),
      );
}

/// Customer ka extra contact number (haath se add/edit hota hai).
class ExtraContact {
  String label; // jaise: "Bhai", "Dukaan", "Ghar"
  String phone;

  ExtraContact({this.label = '', this.phone = ''});

  Map<String, dynamic> toMap() => {'label': label, 'phone': phone};

  factory ExtraContact.fromMap(Map<String, dynamic> m) => ExtraContact(
        label: (m['label'] ?? '').toString(),
        phone: (m['phone'] ?? '').toString(),
      );
}

class CollectionEntry {
  final String receiptNo;
  final String date;
  final double prevBalance;
  final double collected;
  final double balance;
  final String receivedBy;

  CollectionEntry({
    this.receiptNo = '',
    this.date = '',
    this.prevBalance = 0,
    this.collected = 0,
    this.balance = 0,
    this.receivedBy = '',
  });

  Map<String, dynamic> toMap() => {
        'receiptNo': receiptNo,
        'date': date,
        'prevBalance': prevBalance,
        'collected': collected,
        'balance': balance,
        'receivedBy': receivedBy,
      };

  factory CollectionEntry.fromMap(Map<String, dynamic> m) => CollectionEntry(
        receiptNo: (m['receiptNo'] ?? '').toString(),
        date: (m['date'] ?? '').toString(),
        prevBalance: _num(m['prevBalance']),
        collected: _num(m['collected']),
        balance: _num(m['balance']),
        receivedBy: (m['receivedBy'] ?? '').toString(),
      );
}

double _num(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) {
    return double.tryParse(v.replaceAll(',', '').trim()) ?? 0;
  }
  return 0;
}

class Customer {
  String accountNo; // "A/C No." — unique key across both documents
  String customerCode;
  String name;
  String fatherName; // S/O or W/O
  String cell; // also the WhatsApp number
  String telRes;
  String cnic;
  String resAddress;
  String offAddress;
  String occupation;
  double monthlyIncome;

  // Product & plan
  String company;
  String item; // MOBILE / LED / BIKE ...
  String modelNo;
  String serialNo;
  double price;
  double advance;
  double monthlyInstallment;
  int durationMonths;
  String accountDate;

  // Account section extras (as printed)
  String dueDate;
  double dueAmount;
  String processNo;
  String preAccountNo;
  String fineTime;

  // Customer section extras (as printed)
  bool houseOwner;
  bool married;
  String marketingOfficer;
  String verifiedBy;
  String deliveredBy;

  // Monthly status — refreshed by each outstanding import
  double balance;
  double osAmount;
  double paid;
  double currentDue;
  String lastInstDate;
  String officer; // recovery/inquiry officer
  AccountStatus status;
  bool needsDetail; // true when created from outstanding-only import

  List<Guarantor> guarantors;
  List<CollectionEntry> collections;

  /// Haath se add/edit hone wale extra contact numbers.
  List<ExtraContact> extraContacts;

  /// Remarks — additional information, kabhi bhi edit ho sakti hai.
  String notes;

  Customer({
    required this.accountNo,
    this.customerCode = '',
    this.name = '',
    this.fatherName = '',
    this.cell = '',
    this.telRes = '',
    this.cnic = '',
    this.resAddress = '',
    this.offAddress = '',
    this.occupation = '',
    this.monthlyIncome = 0,
    this.company = '',
    this.item = '',
    this.modelNo = '',
    this.serialNo = '',
    this.price = 0,
    this.advance = 0,
    this.monthlyInstallment = 0,
    this.durationMonths = 0,
    this.accountDate = '',
    this.dueDate = '',
    this.dueAmount = 0,
    this.processNo = '',
    this.preAccountNo = '',
    this.fineTime = '',
    this.houseOwner = false,
    this.married = false,
    this.marketingOfficer = '',
    this.verifiedBy = '',
    this.deliveredBy = '',
    this.balance = 0,
    this.osAmount = 0,
    this.paid = 0,
    this.currentDue = 0,
    this.lastInstDate = '',
    this.officer = '',
    this.status = AccountStatus.active,
    this.needsDetail = false,
    List<Guarantor>? guarantors,
    List<CollectionEntry>? collections,
    List<ExtraContact>? extraContacts,
    this.notes = '',
  })  : guarantors = guarantors ?? [],
        collections = collections ?? [],
        extraContacts = extraContacts ?? [];

  /// WhatsApp-ready number: 03XXXXXXXXX -> 92XXXXXXXXX
  String get whatsappNumber {
    var d = cell.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('03') && d.length == 11) return '92${d.substring(1)}';
    if (d.startsWith('923') && d.length == 12) return d;
    return d;
  }

  Map<String, dynamic> toMap() => {
        'accountNo': accountNo,
        'customerCode': customerCode,
        'name': name,
        'fatherName': fatherName,
        'cell': cell,
        'telRes': telRes,
        'cnic': cnic,
        'resAddress': resAddress,
        'offAddress': offAddress,
        'occupation': occupation,
        'monthlyIncome': monthlyIncome,
        'company': company,
        'item': item,
        'modelNo': modelNo,
        'serialNo': serialNo,
        'price': price,
        'advance': advance,
        'monthlyInstallment': monthlyInstallment,
        'durationMonths': durationMonths,
        'accountDate': accountDate,
        'dueDate': dueDate,
        'dueAmount': dueAmount,
        'processNo': processNo,
        'preAccountNo': preAccountNo,
        'fineTime': fineTime,
        'houseOwner': houseOwner ? 1 : 0,
        'married': married ? 1 : 0,
        'marketingOfficer': marketingOfficer,
        'verifiedBy': verifiedBy,
        'deliveredBy': deliveredBy,
        'balance': balance,
        'osAmount': osAmount,
        'paid': paid,
        'currentDue': currentDue,
        'lastInstDate': lastInstDate,
        'officer': officer,
        'status': status.index,
        'needsDetail': needsDetail ? 1 : 0,
        'guarantors': guarantors.map((g) => g.toMap()).toList(),
        'collections': collections.map((c) => c.toMap()).toList(),
        'extraContacts':
            extraContacts.map((e) => e.toMap()).toList(),
        'notes': notes,
      };

  factory Customer.fromMap(Map<String, dynamic> m) => Customer(
        accountNo: (m['accountNo'] ?? '').toString(),
        customerCode: (m['customerCode'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        fatherName: (m['fatherName'] ?? '').toString(),
        cell: (m['cell'] ?? '').toString(),
        telRes: (m['telRes'] ?? '').toString(),
        cnic: (m['cnic'] ?? '').toString(),
        resAddress: (m['resAddress'] ?? '').toString(),
        offAddress: (m['offAddress'] ?? '').toString(),
        occupation: (m['occupation'] ?? '').toString(),
        monthlyIncome: _num(m['monthlyIncome']),
        company: (m['company'] ?? '').toString(),
        item: (m['item'] ?? '').toString(),
        modelNo: (m['modelNo'] ?? '').toString(),
        serialNo: (m['serialNo'] ?? '').toString(),
        price: _num(m['price']),
        advance: _num(m['advance']),
        monthlyInstallment: _num(m['monthlyInstallment']),
        durationMonths: (m['durationMonths'] is int)
            ? m['durationMonths'] as int
            : int.tryParse('${m['durationMonths']}') ?? 0,
        accountDate: (m['accountDate'] ?? '').toString(),
        dueDate: (m['dueDate'] ?? '').toString(),
        dueAmount: _num(m['dueAmount']),
        processNo: (m['processNo'] ?? '').toString(),
        preAccountNo: (m['preAccountNo'] ?? '').toString(),
        fineTime: (m['fineTime'] ?? '').toString(),
        houseOwner: (m['houseOwner'] ?? 0) == 1,
        married: (m['married'] ?? 0) == 1,
        marketingOfficer: (m['marketingOfficer'] ?? '').toString(),
        verifiedBy: (m['verifiedBy'] ?? '').toString(),
        deliveredBy: (m['deliveredBy'] ?? '').toString(),
        balance: _num(m['balance']),
        osAmount: _num(m['osAmount']),
        paid: _num(m['paid']),
        currentDue: _num(m['currentDue']),
        lastInstDate: (m['lastInstDate'] ?? '').toString(),
        officer: (m['officer'] ?? '').toString(),
        status: AccountStatus.values[
            (m['status'] is int ? m['status'] as int : 0) %
                AccountStatus.values.length],
        needsDetail: (m['needsDetail'] ?? 0) == 1,
        guarantors: ((m['guarantors'] as List?) ?? [])
            .map((e) => Guarantor.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        collections: ((m['collections'] as List?) ?? [])
            .map((e) =>
                CollectionEntry.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        extraContacts: ((m['extraContacts'] as List?) ?? [])
            .map((e) =>
                ExtraContact.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        notes: (m['notes'] ?? '').toString(),
      );
}
