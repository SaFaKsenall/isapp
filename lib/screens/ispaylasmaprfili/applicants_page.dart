import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:myapp/model/user_model.dart';
import 'package:myapp/screens/ispaylasmaprfili/job_profile_page.dart';

class ApplicantsPage extends StatefulWidget {
  final String jobId;

  const ApplicantsPage({super.key, required this.jobId});

  @override
  _ApplicantsPageState createState() => _ApplicantsPageState();
}

class _ApplicantsPageState extends State<ApplicantsPage> {
  List<Map<String, dynamic>> _applicants = [];

  @override
  void initState() {
    super.initState();
    _fetchApplicants();
  }

  Future<void> _fetchApplicants() async {
    try {
      QuerySnapshot applicationsSnapshot = await FirebaseFirestore.instance
          .collection('job_applications')
          .where('jobId', isEqualTo: widget.jobId)
          .get();

      List<Map<String, dynamic>> applicantsList = [];
      for (var doc in applicationsSnapshot.docs) {
        try {
          DocumentSnapshot userSnapshot = await FirebaseFirestore.instance
              .collection('users')
              .doc(doc['applicantId'])
              .get();

          // Güvenli veri çekme
          Map<String, dynamic> userData =
              userSnapshot.data() as Map<String, dynamic>? ?? {};

          applicantsList.add({
            'applicationId': doc.id,
            'userId': doc['applicantId'],
            'username': userData['username'] ?? 'Bilinmeyen Kullanıcı',
            // Güvenli profil resmi kontrolü
            'profileImage':
                userData['profileImageUrl'] ?? userData['profileImage'] ?? '',
            'applicationDate': doc['applicationDate'],
          });
        } catch (innerError) {
          print('Başvuru işleminde hata: $innerError');
        }
      }

      setState(() {
        _applicants = applicantsList;
      });
    } catch (e) {
      print('Başvuranları getirirken hata: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Başvuranlar yüklenirken hata oluştu')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Başvuranlar (${_applicants.length})'),
        centerTitle: true,
      ),
      body: _applicants.isEmpty
          ? const Center(child: Text('Henüz başvuru yok'))
          : ListView.builder(
              itemCount: _applicants.length,
              itemBuilder: (context, index) {
                var applicant = _applicants[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: applicant['profileImage'].isNotEmpty
                        ? NetworkImage(applicant['profileImage'])
                        : null,
                    child: applicant['profileImage'].isEmpty
                        ? const Icon(Icons.person)
                        : null,
                  ),
                  title: Text(applicant['username']),
                  subtitle: Text(
                    'Başvuru Tarihi: ${_formatApplicationDate(applicant['applicationDate'])}',
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => JobProfilePage(
                          user: UserModel(
                            uid: applicant['userId'],
                            username: applicant['username'],
                            profileImageUrl: applicant['profileImage'],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  String _formatApplicationDate(Timestamp? timestamp) {
    if (timestamp == null) return 'Tarih bilinmiyor';

    DateTime date = timestamp.toDate();
    return '${date.day}.${date.month}.${date.year}';
  }
}
