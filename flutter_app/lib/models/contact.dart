class Contact {
  final String id;
  final String name;
  final String phone;

  const Contact({required this.id, required this.name, required this.phone});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'phone': phone};

  factory Contact.fromJson(Map<String, dynamic> json) => Contact(
        id: json['id'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String,
      );

  Contact copyWith({String? id, String? name, String? phone}) => Contact(
        id: id ?? this.id,
        name: name ?? this.name,
        phone: phone ?? this.phone,
      );
}
