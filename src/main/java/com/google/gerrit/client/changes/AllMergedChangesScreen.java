// Copyright 2008 Google Inc.
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

package com.google.gerrit.client.changes;

import com.google.gerrit.client.data.SingleListChangeInfo;
import com.google.gerrit.client.reviewdb.Change;
import com.google.gerrit.client.rpc.GerritCallback;


public class AllMergedChangesScreen extends AllSingleListScreen {
  public AllMergedChangesScreen(final String positionToken) {
    super(Util.C.allMergedChanges(), "all,merged", positionToken);
  }

  @Override
  protected void loadPrev() {
    Util.LIST_SVC.allClosedPrev(Change.Status.MERGED, pos, pageSize,
        new GerritCallback<SingleListChangeInfo>() {
          public void onSuccess(final SingleListChangeInfo result) {
            display(result);
          }
        });
  }

  @Override
  protected void loadNext() {
    Util.LIST_SVC.allClosedNext(Change.Status.MERGED, pos, pageSize,
        new GerritCallback<SingleListChangeInfo>() {
          public void onSuccess(final SingleListChangeInfo result) {
            display(result);
          }
        });
  }
}