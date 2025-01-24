import 'package:cloud_firestore/cloud_firestore.dart';

class Job {
  final String id;
  final String jobName;
  final String jobDescription;
  final double jobPrice;
  String? neighborhood;
  final String employerId;
  final List<Review>? reviews;
  final String? username;
  final String? profileImage;
  final String category;
  final double budget;
  final int likes;
  final int comments;
  final GeoPoint? location;
  final DateTime? createdAt;
  final String status;
  final bool hasLocation;
  double? distance;
  double? latitude;
  double? longitude;

  Job({
    required this.id,
    required this.jobName,
    required this.jobDescription,
    required this.jobPrice,
    required this.employerId,
    this.neighborhood,
    this.reviews,
    this.username,
    this.profileImage,
    this.category = 'Uncategorized',
    this.budget = 0.0,
    this.likes = 0,
    this.comments = 0,
    this.location,
    this.createdAt,
    this.status = 'active',
    this.hasLocation = false,
    this.distance,
    this.latitude,
    this.longitude,
  });

  factory Job.fromMap(Map<String, dynamic> map) {
    return Job(
      id: map['id'] ?? '',
      jobName: map['jobName'] ?? '',
      jobDescription: map['jobDescription'] ?? '',
      jobPrice: (map['jobPrice'] as num?)?.toDouble() ?? 0.0,
      employerId: map['employerId'] ?? '',
      neighborhood: map['neighborhood'],
      username: map['username'],
      profileImage: map['profileImage'],
      category: map['category'] ?? 'Uncategorized',
      budget: (map['budget'] as num?)?.toDouble() ?? 0.0,
      likes: (map['likes'] as num?)?.toInt() ?? 0,
      comments: (map['comments'] as num?)?.toInt() ?? 0,
      location: map['location'] as GeoPoint?,
      createdAt: map['createdAt'] != null
          ? (map['createdAt'] as Timestamp).toDate()
          : null,
      status: map['status'] ?? 'active',
      reviews: map['reviews'] != null
          ? (map['reviews'] as List)
              .map((review) => Review.fromMap(review as Map<String, dynamic>))
              .toList()
          : null,
      hasLocation: map['hasLocation'] == 1,
      distance: (map['distance'] as num?)?.toDouble(),
      latitude: map['latitude'],
      longitude: map['longitude'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'jobName': jobName,
      'jobDescription': jobDescription,
      'jobPrice': jobPrice,
      'employerId': employerId,
      'neighborhood': neighborhood,
      'username': username,
      'profileImage': profileImage,
      'category': category,
      'budget': budget,
      'likes': likes,
      'comments': comments,
      'location': location,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'status': status,
      'reviews': reviews?.map((review) => review.toMap()).toList(),
      'hasLocation': hasLocation ? 1 : 0,
      'distance': distance,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  static Job fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Job.fromMap({
      'id': doc.id,
      ...data,
    });
  }

  Job copyWith({
    String? id,
    String? jobName,
    String? jobDescription,
    double? jobPrice,
    String? neighborhood,
    String? employerId,
    List<Review>? reviews,
    String? username,
    String? profileImage,
    String? category,
    double? budget,
    int? likes,
    int? comments,
    GeoPoint? location,
    DateTime? createdAt,
    String? status,
    double? distance,
    double? latitude,
    double? longitude,
  }) {
    return Job(
        id: id ?? this.id,
        jobName: jobName ?? this.jobName,
        jobDescription: jobDescription ?? this.jobDescription,
        jobPrice: jobPrice ?? this.jobPrice,
        employerId: employerId ?? this.employerId,
        neighborhood: neighborhood ?? this.neighborhood,
        reviews: reviews ?? this.reviews,
        username: username ?? this.username,
        profileImage: profileImage ?? this.profileImage,
        category: category ?? this.category,
        budget: budget ?? this.budget,
        likes: likes ?? this.likes,
        comments: comments ?? this.comments,
        location: location ?? this.location,
        createdAt: createdAt ?? this.createdAt,
        status: status ?? this.status,
        distance: distance ?? this.distance,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude);
  }

  factory Job.fromJson(Map<String, dynamic> json) {
    return Job(
      id: json['id'],
      jobName: json['jobName'],
      jobDescription: json['jobDescription'],
      jobPrice: json['jobPrice'].toDouble(),
      employerId: json['employerId'],
      category: json['category'] ?? '',
      neighborhood: json['neighborhood'],
      location: json['location'] != null
          ? GeoPoint(
              json['location']['latitude'], json['location']['longitude'])
          : null,
      hasLocation: json['hasLocation'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'jobName': jobName,
      'jobDescription': jobDescription,
      'jobPrice': jobPrice,
      'employerId': employerId,
      'category': category,
      'neighborhood': neighborhood,
      'location': location != null
          ? {'latitude': location!.latitude, 'longitude': location!.longitude}
          : null,
      'hasLocation': hasLocation,
    };
  }
}

class Review {
  final String employerId;
  final String reviewerId;
  final double rating;
  final String comment;
  final String? reviewerUsername;
  final String? reviewerProfileImage;
  final DateTime? createdAt;
  final String? jobId;
  final String status;

  Review({
    required this.employerId,
    required this.reviewerId,
    required this.rating,
    required this.comment,
    this.reviewerUsername,
    this.reviewerProfileImage,
    this.createdAt,
    this.jobId,
    this.status = 'active',
  });

  factory Review.fromMap(Map<String, dynamic> map) {
    return Review(
      employerId: map['employerId'] ?? '',
      reviewerId: map['reviewerId'] ?? '',
      rating: (map['rating'] as num?)?.toDouble() ?? 0.0,
      comment: map['comment'] ?? '',
      reviewerUsername: map['reviewerUsername'],
      reviewerProfileImage: map['reviewerProfileImage'],
      createdAt: map['createdAt'] != null
          ? (map['createdAt'] as Timestamp).toDate()
          : null,
      jobId: map['jobId'],
      status: map['status'] ?? 'active',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'employerId': employerId,
      'reviewerId': reviewerId,
      'rating': rating,
      'comment': comment,
      'reviewerUsername': reviewerUsername,
      'reviewerProfileImage': reviewerProfileImage,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'jobId': jobId,
      'status': status,
    };
  }

  Review copyWith({
    String? employerId,
    String? reviewerId,
    double? rating,
    String? comment,
    String? reviewerUsername,
    String? reviewerProfileImage,
    DateTime? createdAt,
    String? jobId,
    String? status,
  }) {
    return Review(
      employerId: employerId ?? this.employerId,
      reviewerId: reviewerId ?? this.reviewerId,
      rating: rating ?? this.rating,
      comment: comment ?? this.comment,
      reviewerUsername: reviewerUsername ?? this.reviewerUsername,
      reviewerProfileImage: reviewerProfileImage ?? this.reviewerProfileImage,
      createdAt: createdAt ?? this.createdAt,
      jobId: jobId ?? this.jobId,
      status: status ?? this.status,
    );
  }

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      employerId: json['employerId'],
      reviewerId: json['reviewerId'],
      rating: json['rating'].toDouble(),
      comment: json['comment'],
      reviewerUsername: json['reviewerUsername'],
      reviewerProfileImage: json['reviewerProfileImage'],
      createdAt:
          json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
      jobId: json['jobId'],
      status: json['status'] ?? 'active',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'employerId': employerId,
      'reviewerId': reviewerId,
      'rating': rating,
      'comment': comment,
      'reviewerUsername': reviewerUsername,
      'reviewerProfileImage': reviewerProfileImage,
      'createdAt': createdAt?.toIso8601String(),
      'jobId': jobId,
      'status': status,
    };
  }
}
