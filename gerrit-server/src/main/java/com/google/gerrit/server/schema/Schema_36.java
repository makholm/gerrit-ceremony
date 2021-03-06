// Copyright (C) 2010 The Android Open Source Project
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package com.google.gerrit.server.schema;

import com.google.gerrit.reviewdb.ReviewDb;
import com.google.gwtorm.jdbc.JdbcSchema;
import com.google.gwtorm.schema.sql.DialectMySQL;
import com.google.inject.Inject;
import com.google.inject.Provider;

import java.sql.SQLException;
import java.sql.Statement;

public class Schema_36 extends SchemaVersion {
  @Inject
  Schema_36(Provider<Schema_35> prior) {
    super(prior);
  }

  @Override
  protected void migrateData(ReviewDb db, UpdateUI ui) throws SQLException {
    Statement stmt = ((JdbcSchema) db).getConnection().createStatement();
    try {
      if (((JdbcSchema) db).getDialect() instanceof DialectMySQL) {
        stmt.execute("DROP INDEX account_project_watches_ntNew ON account_project_watches");
        stmt.execute("DROP INDEX account_project_watches_ntCmt ON account_project_watches");
        stmt.execute("DROP INDEX account_project_watches_ntSub ON account_project_watches");
      } else {
        stmt.execute("DROP INDEX account_project_watches_ntNew");
        stmt.execute("DROP INDEX account_project_watches_ntCmt");
        stmt.execute("DROP INDEX account_project_watches_ntSub");
      }
      stmt.execute("CREATE INDEX account_project_watches_byProject"
          + " ON account_project_watches (project_name)");
    } finally {
      stmt.close();
    }
  }
}
