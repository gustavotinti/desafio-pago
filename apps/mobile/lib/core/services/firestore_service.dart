import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference get users => _firestore.collection('users');
  CollectionReference get withdrawals => _firestore.collection('withdrawals');
  CollectionReference get challenges => _firestore.collection('challenges');
  CollectionReference get votes => _firestore.collection('votes');
}